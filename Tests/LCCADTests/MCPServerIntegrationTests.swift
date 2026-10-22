import XCTest
import MCP
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

    private func post(_ body: [String: Any], headers: [String: String] = [:],
                      session: URLSession = .shared) async throws -> (Int, [String: Any]?) {
        var request = URLRequest(url: URL(string: MCPServerController.endpointURL(port: port))!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (status, json)
    }

    private func rpc(_ method: String, _ params: [String: Any] = [:],
                     session: URLSession = .shared) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        let (status, json) = try await post(
            ["jsonrpc": "2.0", "id": id, "method": method, "params": params],
            headers: ["MCP-Protocol-Version": "2025-06-18"], session: session)
        XCTAssertEqual(status, 200)
        return try XCTUnwrap(json)
    }

    private func initialize(session: URLSession = .shared) async throws {
        let result = try await rpc("initialize", [
            "protocolVersion": "2025-06-18",
            "capabilities": [:],
            "clientInfo": ["name": "test", "version": "1"],
        ], session: session)
        XCTAssertNotNil(result["result"], "\(result)")
        let (status, _) = try await post(["jsonrpc": "2.0", "method": "notifications/initialized"],
                                         headers: ["MCP-Protocol-Version": "2025-06-18"], session: session)
        XCTAssertEqual(status, 202)
    }

    /// add_shapes で線を 1 本足し、ツールの結果がエラーでないかを返す
    private func addLine(session: URLSession = .shared) async throws -> Bool {
        let call = try await rpc("tools/call", [
            "name": "add_shapes",
            "arguments": ["shapes": [["type": "line", "start": [0, 0], "end": [25, 0]]]],
        ], session: session)
        let result = try XCTUnwrap(call["result"] as? [String: Any], "\(call)")
        return result["isError"] as? Bool != true
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

    /// 別々の接続の 2 つのクライアントが、どちらも initialize してツールを呼べる。
    /// 2 つ目が initialize したあとも 1 つ目は使え、同時に呼んでも答える (#89)
    func testTwoClientsCanInitializeAndCallTools() async throws {
        let first = URLSession(configuration: .ephemeral)
        let second = URLSession(configuration: .ephemeral)
        defer {
            first.invalidateAndCancel()
            second.invalidateAndCancel()
        }

        try await initialize(session: first)
        try await initialize(session: second)
        let firstAdded = try await addLine(session: first)
        XCTAssertTrue(firstAdded)
        let secondAdded = try await addLine(session: second)
        XCTAssertTrue(secondAdded)

        // MainActor の上の Task 2 つで、HTTP の要求を同時に出す
        let firstAgain = Task { try await self.addLine(session: first) }
        let secondAgain = Task { try await self.addLine(session: second) }
        let concurrent = try await [firstAgain.value, secondAgain.value]
        XCTAssertEqual(concurrent, [true, true])
        XCTAssertEqual(editor.document.layers[0].shapes.count, 4)
    }

    /// 要求を受けたあとに止められたら、ツールを実行しない(review #91)
    func testToolCallFromStoppedRunIsRejected() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": [
                "name": "add_shapes",
                "arguments": ["shapes": [["type": "line", "start": [0, 0], "end": [25, 0]]]],
            ] as [String: Any],
        ] as [String: Any])
        let request = HTTPRequest(
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json, text/event-stream",
                "MCP-Protocol-Version": "2025-06-18",
            ],
            body: body,
            path: MCPHTTPListener.endpointPath
        )
        // 起動の世代は 1 以上なので、-1 は止められた(古い)起動として扱われる
        let response = await MCPServerController.respond(to: request, controller: controller, runID: -1)
        let data = try XCTUnwrap(response.bodyData)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any], "\(json)")
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertTrue(editor.document.layers[0].shapes.isEmpty)
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
