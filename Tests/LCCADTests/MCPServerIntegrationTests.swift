import XCTest
@testable import LCCAD

/// 待ち受けを実際に立て、HTTP で MCP を呼ぶ結合テスト (#79)
@MainActor
final class MCPServerIntegrationTests: XCTestCase {

    private var controller: MCPServerController!
    private var editor: EditorViewModel!
    private var fileDocument: LCCADFileDocument!
    private var port = 0
    private var nextID = 1

    override func setUp() async throws {
        fileDocument = LCCADFileDocument()
        editor = EditorViewModel(document: fileDocument.data)
        editor.fileDocument = fileDocument
        controller = MCPServerController()
        controller.editor = editor
        // ほかのテストやアプリと重ならないように、テストごとに高い番号のポートを使う
        port = Int.random(in: 50000...60000)
        controller.start(port: port)
        try await waitForRunning()
    }

    override func tearDown() async throws {
        controller.stop()
    }

    private func waitForRunning() async throws {
        for _ in 0..<100 {
            if case .running = controller.status { return }
            if case .failed(let message) = controller.status { return XCTFail("server failed: \(message)") }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("server did not start: \(controller.status)")
    }

    private func post(_ body: [String: Any], headers: [String: String] = [:]) async throws -> (Int, [String: Any]?) {
        var request = URLRequest(url: URL(string: MCPServerController.endpointURL(port: port))!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (status, json)
    }

    private func rpc(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        defer { nextID += 1 }
        let (status, json) = try await post(
            ["jsonrpc": "2.0", "id": nextID, "method": method, "params": params],
            headers: ["MCP-Protocol-Version": "2025-06-18"])
        XCTAssertEqual(status, 200)
        return try XCTUnwrap(json)
    }

    private func initialize() async throws {
        let result = try await rpc("initialize", [
            "protocolVersion": "2025-06-18",
            "capabilities": [:],
            "clientInfo": ["name": "test", "version": "1"],
        ])
        XCTAssertNotNil(result["result"], "\(result)")
        let (status, _) = try await post(["jsonrpc": "2.0", "method": "notifications/initialized"],
                                         headers: ["MCP-Protocol-Version": "2025-06-18"])
        XCTAssertEqual(status, 202)
    }

    func testListAndCallToolsOverHTTP() async throws {
        try await initialize()

        let list = try await rpc("tools/list")
        let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }), Set(MCPToolCatalog.tools.map(\.name)))

        let call = try await rpc("tools/call", [
            "name": "add_shapes",
            "arguments": ["shapes": [["type": "line", "start": [0, 0], "end": [25, 0]]]],
        ])
        let result = try XCTUnwrap(call["result"] as? [String: Any])
        XCTAssertNotEqual(result["isError"] as? Bool, true, "\(result)")
        XCTAssertEqual(editor.document.layers[0].shapes.count, 1)
    }

    /// 1 つ目のクライアントが initialize したあとでも、2 つ目のクライアントが
    /// initialize してツールを呼べる (#89)
    func testSecondClientCanInitialize() async throws {
        try await initialize()
        try await initialize()

        let call = try await rpc("tools/call", [
            "name": "add_shapes",
            "arguments": ["shapes": [["type": "line", "start": [0, 0], "end": [25, 0]]]],
        ])
        let result = try XCTUnwrap(call["result"] as? [String: Any], "\(call)")
        XCTAssertNotEqual(result["isError"] as? Bool, true, "\(result)")
        XCTAssertEqual(editor.document.layers[0].shapes.count, 1)
    }

    /// ブラウザからの要求(localhost 以外の Origin)は、ツールを実行する前に弾く
    func testRejectsBrowserOrigin() async throws {
        let (status, _) = try await post(
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]],
            headers: ["Origin": "https://evil.example"])
        XCTAssertEqual(status, 403)
    }

    func testUnknownPathIsNotFound() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/other")!)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
    }

    func testStopClosesThePort() async throws {
        controller.stop()
        XCTAssertEqual(controller.status, .stopped)
        try await Task.sleep(for: .milliseconds(100))
        var request = URLRequest(url: URL(string: MCPServerController.endpointURL(port: port))!)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        do {
            _ = try await URLSession.shared.data(for: request)
            XCTFail("the port is still open")
        } catch {
            // 接続できなければよい
        }
    }

    func testInvalidPortFails() {
        controller.start(port: 80)
        guard case .failed = controller.status else { return XCTFail("\(controller.status)") }
    }
}
