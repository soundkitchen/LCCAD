import Foundation
import Network
import MCP

/// 127.0.0.1 で HTTP/1.1 を待ち受け、`/mcp` へのリクエストを MCP のトランスポートに渡す
/// 最小限の HTTP サーバー (#79)。MCP Swift SDK の HTTP サーバー用トランスポートは
/// 待ち受けを持たないので、ここで用意する。
///
/// 状態はすべて `queue` の上でだけ触る。
final class MCPHTTPListener: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    enum Event: Sendable, Equatable {
        case ready(port: UInt16)
        case failed(String)
    }

    /// MCP のエンドポイントのパス
    static let endpointPath = "/mcp"

    private let queue = DispatchQueue(label: "org.izukawa.LCCAD.mcp-listener")
    private let handler: Handler
    private let onEvent: @Sendable (Event) -> Void
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ListenerConnection] = [:]

    init(handler: @escaping Handler, onEvent: @escaping @Sendable (Event) -> Void) {
        self.handler = handler
        self.onEvent = onEvent
    }

    /// 待ち受けを始める。結果は `onEvent` で知らせる
    func start(port: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port), port != 0 else {
            throw MCPError.invalidParams("Invalid port: \(port)")
        }
        let parameters = NWParameters.tcp
        // ループバックにだけ結び付け、ほかのマシンからは接続できないようにする
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onEvent(.ready(port: port))
            case .failed(let error):
                self.onEvent(.failed(error.localizedDescription))
                self.stopOnQueue()
            case .waiting(let error):
                // ポートが使用中などで待っている。待ち続けずに失敗として扱う
                self.onEvent(.failed(error.localizedDescription))
                self.stopOnQueue()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        queue.async {
            self.listener = listener
            listener.start(queue: self.queue)
        }
    }

    /// 待ち受けと、開いている接続をすべて閉じる
    func stop() {
        queue.async { self.stopOnQueue() }
    }

    private func stopOnQueue() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections = [:]
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = ListenerConnection(
            connection: nwConnection,
            queue: queue,
            handler: handler,
            onClose: { [weak self] id in self?.connections[id] = nil }
        )
        connections[ObjectIdentifier(connection)] = connection
        connection.start()
    }
}

/// 1 本の TCP 接続。リクエストを 1 件ずつ順に処理する。`queue` の上でだけ触る
private final class ListenerConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: MCPHTTPListener.Handler
    private let onClose: (ObjectIdentifier) -> Void
    private var buffer = Data()
    private var isHandling = false
    private var isClosed = false
    private var receivedEOF = false

    init(connection: NWConnection, queue: DispatchQueue,
         handler: @escaping MCPHTTPListener.Handler,
         onClose: @escaping (ObjectIdentifier) -> Void) {
        self.connection = connection
        self.queue = queue
        self.handler = handler
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func cancel() {
        close()
    }

    private func receive() {
        guard !isClosed, !receivedEOF else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
            }
            if isComplete || error != nil {
                self.receivedEOF = true
            }
            self.processBuffer()
        }
    }

    private func processBuffer() {
        guard !isClosed, !isHandling else { return }
        switch HTTPMessage.parseRequest(buffer) {
        case .incomplete:
            if receivedEOF {
                close()
            } else {
                receive()
            }
        case .failure(let status):
            send(status: status, headers: [:], body: nil, keepAlive: false)
        case .request(let request, let consumed):
            buffer = buffer.subdata(in: (buffer.startIndex + consumed)..<buffer.endIndex)
            guard request.path == MCPHTTPListener.endpointPath else {
                send(status: 404, headers: [:], body: nil, keepAlive: request.keepAlive)
                return
            }
            isHandling = true
            let mcpRequest = HTTPRequest(
                method: request.method,
                headers: request.headers,
                body: request.body.isEmpty ? nil : request.body,
                path: request.path
            )
            let handler = self.handler
            Task {
                let response = await handler(mcpRequest)
                self.queue.async {
                    self.isHandling = false
                    self.send(response, keepAlive: request.keepAlive)
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, keepAlive: Bool) {
        if case .stream = response {
            // ステートレスのトランスポートは SSE を返さない
            send(status: 500, headers: [:], body: nil, keepAlive: false)
            return
        }
        send(status: response.statusCode, headers: response.headers, body: response.bodyData, keepAlive: keepAlive)
    }

    private func send(status: Int, headers: [String: String], body: Data?, keepAlive: Bool) {
        guard !isClosed else { return }
        let data = HTTPMessage.serializeResponse(status: status, headers: headers, body: body, keepAlive: keepAlive)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil || !keepAlive {
                self.close()
            } else {
                // 届いている次のリクエストがあれば続けて処理する
                self.processBuffer()
            }
        })
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose(ObjectIdentifier(self))
    }
}
