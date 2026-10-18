import XCTest
@testable import LCCAD

/// MCP の待ち受けが使う HTTP/1.1 の解析と組み立て (#79)
final class HTTPMessageTests: XCTestCase {

    private func data(_ text: String) -> Data { Data(text.utf8) }

    private func parsed(_ text: String) -> (HTTPMessage.Request, Int)? {
        if case .request(let request, let consumed) = HTTPMessage.parseRequest(data(text)) {
            return (request, consumed)
        }
        return nil
    }

    func testParsesRequestWithContentLength() throws {
        let text = "POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1:47821\r\nContent-Length: 4\r\n\r\nbody"
        let (request, consumed) = try XCTUnwrap(parsed(text))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(request.header("host"), "127.0.0.1:47821")
        XCTAssertEqual(request.body, data("body"))
        XCTAssertTrue(request.keepAlive)
        XCTAssertEqual(consumed, text.utf8.count)
    }

    func testIncompleteUntilHeadersAndBodyArrive() {
        XCTAssertEqual(HTTPMessage.parseRequest(data("POST /mcp HTTP/1.1\r\nContent-Length: 4\r\n")), .incomplete)
        XCTAssertEqual(HTTPMessage.parseRequest(data("POST /mcp HTTP/1.1\r\nContent-Length: 4\r\n\r\nbo")), .incomplete)
    }

    func testLeavesFollowingPipelinedRequestInBuffer() throws {
        let first = "POST /mcp HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}"
        let (_, consumed) = try XCTUnwrap(parsed(first + "GET /mcp HTTP/1.1\r\n\r\n"))
        XCTAssertEqual(consumed, first.utf8.count)
    }

    func testDecodesChunkedBody() throws {
        let text = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2;ext=1\r\nde\r\n0\r\n\r\n"
        let (request, consumed) = try XCTUnwrap(parsed(text))
        XCTAssertEqual(request.body, data("abcde"))
        XCTAssertEqual(consumed, text.utf8.count)
    }

    func testChunkedBodyIsIncompleteUntilTerminatorArrives() {
        let text = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n"
        XCTAssertEqual(HTTPMessage.parseRequest(data(text)), .incomplete)
    }

    func testConnectionHeaderControlsKeepAlive() throws {
        XCTAssertFalse(try XCTUnwrap(parsed("GET /mcp HTTP/1.1\r\nConnection: close\r\n\r\n")).0.keepAlive)
        XCTAssertFalse(try XCTUnwrap(parsed("GET /mcp HTTP/1.0\r\n\r\n")).0.keepAlive)
        XCTAssertTrue(try XCTUnwrap(parsed("GET /mcp HTTP/1.0\r\nConnection: keep-alive\r\n\r\n")).0.keepAlive)
    }

    func testRejectsMalformedRequests() {
        XCTAssertEqual(HTTPMessage.parseRequest(data("NONSENSE\r\n\r\n")), .failure(status: 400))
        XCTAssertEqual(HTTPMessage.parseRequest(data("GET /mcp HTTP/2\r\n\r\n")), .failure(status: 505))
        XCTAssertEqual(HTTPMessage.parseRequest(data("POST /mcp HTTP/1.1\r\nContent-Length: x\r\n\r\n")), .failure(status: 400))
        XCTAssertEqual(HTTPMessage.parseRequest(data("POST /mcp HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n")), .failure(status: 501))
        let tooLarge = "POST /mcp HTTP/1.1\r\nContent-Length: \(HTTPMessage.maxBodyBytes + 1)\r\n\r\n"
        XCTAssertEqual(HTTPMessage.parseRequest(data(tooLarge)), .failure(status: 413))
    }

    func testRejectsOversizedHeaders() {
        let huge = "GET /mcp HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPMessage.maxHeaderBytes + 1)
        XCTAssertEqual(HTTPMessage.parseRequest(data(huge)), .failure(status: 431))
    }

    func testSerializesResponseWithLengthAndConnection() {
        let response = HTTPMessage.serializeResponse(
            status: 200, headers: ["Content-Type": "application/json", "Content-Length": "999"],
            body: data("{}"), keepAlive: false)
        XCTAssertEqual(String(decoding: response, as: UTF8.self),
                       "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
    }
}
