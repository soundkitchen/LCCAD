import Foundation

/// MCP の待ち受け(`MCPHTTPListener`)が扱う、最小限の HTTP/1.1 の解析と組み立て (#79)。
/// MCP の Streamable HTTP で JSON 応答だけを返すのに必要な範囲に限る
/// (Content-Length と chunked の本文、keep-alive。パイプライン化は順に処理する)
enum HTTPMessage {
    /// ヘッダー部の上限。超えたら 431 を返す
    static let maxHeaderBytes = 64 * 1024
    /// 本文の上限。超えたら 413 を返す
    static let maxBodyBytes = 64 * 1024 * 1024

    struct Request: Equatable, Sendable {
        var method: String
        /// クエリを除いたパス
        var path: String
        var headers: [String: String]
        var body: Data
        /// 応答を返したあとも接続を使い続けるか
        var keepAlive: Bool

        /// 大文字小文字を区別しないヘッダーの取り出し
        func header(_ name: String) -> String? {
            let lowercased = name.lowercased()
            return headers.first { $0.key.lowercased() == lowercased }?.value
        }
    }

    enum ParseResult: Equatable, Sendable {
        /// まだ 1 件分のデータが届いていない
        case incomplete
        /// 1 件を取り出した。`consumed` はバッファの先頭から使ったバイト数
        case request(Request, consumed: Int)
        /// 解析できない。このステータスで応答して接続を閉じる
        case failure(status: Int)
    }

    /// chunked の本文の解析の途中経過。受信のたびに本文を最初からデコードし直さないように、
    /// 接続ごとに持って次の `parseRequest` に渡す(review #86)
    struct ChunkedProgress: Equatable, Sendable {
        /// 次のサイズ行の位置(バッファの先頭からのバイト数)
        var offset: Int
        /// ここまでにデコードした本文
        var body: Data
    }

    /// chunked のサイズ行(拡張を含む)の上限。改行が来ないまま超えたら 400 を返す
    private static let maxChunkSizeLineBytes = 1024

    private static let crlf = Data("\r\n".utf8)
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    /// バッファの先頭から 1 件のリクエストを取り出す
    static func parseRequest(_ buffer: Data) -> ParseResult {
        var progress: ChunkedProgress?
        return parseRequest(buffer, progress: &progress)
    }

    /// バッファの先頭から 1 件のリクエストを取り出す。chunked の本文が届ききっていないときは
    /// `progress` に途中経過を残し、次の呼び出しではその続きからデコードする。
    /// 1 件を取り出すか失敗したら `progress` は nil に戻る
    static func parseRequest(_ buffer: Data, progress: inout ChunkedProgress?) -> ParseResult {
        // 途中までの本文の持ち主をここで引き取る。呼び出し元が参照を持ったままだと、
        // 続きを append するたびに本文全体がコピーされてしまう(COW、review #86)
        var resumed = progress
        progress = nil
        let result = parseRequest(buffer, resuming: &resumed)
        if case .incomplete = result { progress = resumed }
        return result
    }

    /// `resumed` は chunked の途中経過。届ききっていなければ続きの経過を入れて返す
    private static func parseRequest(_ buffer: Data, resuming resumed: inout ChunkedProgress?) -> ParseResult {
        guard let headerEnd = buffer.range(of: headerTerminator) else {
            return buffer.count > maxHeaderBytes ? .failure(status: 431) : .incomplete
        }
        let headerLength = headerEnd.lowerBound - buffer.startIndex
        guard headerLength <= maxHeaderBytes else { return .failure(status: 431) }
        guard let headerText = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .failure(status: 400)
        }

        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3 else { return .failure(status: 400) }
        let method = String(requestLine[0])
        let target = String(requestLine[1])
        let version = String(requestLine[2])
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else { return .failure(status: 505) }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .failure(status: 400) }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .failure(status: 400) }
            // 同じ名前のヘッダーはカンマでつなぐ(RFC 9110 5.3)
            if let existing = headers.first(where: { $0.key.lowercased() == name.lowercased() }) {
                headers[existing.key] = existing.value + ", " + value
            } else {
                headers[name] = value
            }
        }

        let request = Request(method: method, path: target, headers: headers, body: Data(), keepAlive: true)
        let bodyStart = headerEnd.upperBound
        var body = Data()
        var end = bodyStart

        if let transferEncoding = request.header("Transfer-Encoding") {
            guard transferEncoding.lowercased() == "chunked" else { return .failure(status: 501) }
            // 本文を一意に持ったまま append できるよう、途中経過は取り出してから渡す
            var state = resumed ?? ChunkedProgress(offset: bodyStart - buffer.startIndex, body: Data())
            resumed = nil
            switch decodeChunked(buffer, state: &state) {
            case .incomplete:
                resumed = state
                return .incomplete
            case .failure(let status): return .failure(status: status)
            case .decoded(let decodedEnd):
                body = state.body
                end = decodedEnd
            }
        } else if let lengthText = request.header("Content-Length") {
            guard let length = Int(lengthText), length >= 0 else { return .failure(status: 400) }
            guard length <= maxBodyBytes else { return .failure(status: 413) }
            guard buffer.endIndex - bodyStart >= length else { return .incomplete }
            body = buffer.subdata(in: bodyStart..<(bodyStart + length))
            end = bodyStart + length
        }

        let connection = request.header("Connection")?.lowercased()
        let keepAlive = version == "HTTP/1.1" ? connection != "close" : connection == "keep-alive"
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target

        return .request(
            Request(method: method, path: path, headers: headers, body: body, keepAlive: keepAlive),
            consumed: end - buffer.startIndex
        )
    }

    private enum ChunkedResult {
        /// 続きのデータを待つ。途中経過は `state` に残っている
        case incomplete
        case failure(status: Int)
        /// デコードし終えた。本文は `state.body`
        case decoded(end: Data.Index)
    }

    /// `state.offset` のサイズ行から chunked の本文をデコードし、`state.body` の後ろに足していく。
    /// `state` はチャンクを 1 つ読み終えるたびに進める
    private static func decodeChunked(_ buffer: Data, state: inout ChunkedProgress) -> ChunkedResult {
        while true {
            let position = buffer.startIndex + state.offset
            guard let lineEnd = buffer.range(of: crlf, in: position..<buffer.endIndex) else {
                guard buffer.endIndex - position <= maxChunkSizeLineBytes else { return .failure(status: 400) }
                return .incomplete
            }
            guard let sizeLine = String(data: buffer[position..<lineEnd.lowerBound], encoding: .ascii) else {
                return .failure(status: 400)
            }
            // 拡張(";name=value")は読み飛ばす
            let sizeText = sizeLine.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0 else {
                return .failure(status: 400)
            }
            let chunkStart = lineEnd.upperBound
            if size == 0 {
                // トレーラーは読み飛ばす。空行で終わる
                if buffer.endIndex - chunkStart >= 2, buffer[chunkStart..<(chunkStart + 2)] == crlf {
                    return .decoded(end: chunkStart + 2)
                }
                guard let trailerEnd = buffer.range(of: headerTerminator, in: chunkStart..<buffer.endIndex) else {
                    guard buffer.endIndex - chunkStart <= maxHeaderBytes else { return .failure(status: 431) }
                    return .incomplete
                }
                return .decoded(end: trailerEnd.upperBound)
            }
            // state.body.count は maxBodyBytes 以下なので、引き算の形ならあふれない(足し算だと
            // 巨大なサイズ行で Int があふれる、review #86)
            guard size <= maxBodyBytes - state.body.count else { return .failure(status: 413) }
            guard buffer.endIndex - chunkStart >= size + 2 else { return .incomplete }
            guard buffer[(chunkStart + size)..<(chunkStart + size + 2)] == crlf else { return .failure(status: 400) }
            state.body.append(buffer[chunkStart..<(chunkStart + size)])
            state.offset = chunkStart + size + 2 - buffer.startIndex
        }
    }

    /// 応答を組み立てる。Content-Length と Connection はここで付ける
    static func serializeResponse(status: Int, headers: [String: String], body: Data?, keepAlive: Bool) -> Data {
        var text = "HTTP/1.1 \(status) \(reasonPhrase(for: status))\r\n"
        let reserved: Set<String> = ["content-length", "connection", "transfer-encoding"]
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) where !reserved.contains(name.lowercased()) {
            text += "\(name): \(value)\r\n"
        }
        text += "Content-Length: \(body?.count ?? 0)\r\n"
        text += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n\r\n"
        var data = Data(text.utf8)
        if let body { data.append(body) }
        return data
    }

    static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 413: return "Content Too Large"
        case 415: return "Unsupported Media Type"
        case 421: return "Misdirected Request"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 505: return "HTTP Version Not Supported"
        default: return "Status \(status)"
        }
    }
}
