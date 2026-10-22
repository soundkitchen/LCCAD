import Foundation
import MCP

/// エージェント用の操作 API(アプリ内 MCP Server、#79)の起動・停止と状態。
/// 設定画面の Agent タブ(既定はオフ)で有効にすると、127.0.0.1 の `/mcp` で
/// MCP の Streamable HTTP(JSON 応答のみ)を待ち受ける。ブラウザからの要求は
/// SDK の Origin / Host 検証で弾く
@MainActor
final class MCPServerController: ObservableObject {
    static let shared = MCPServerController()

    enum Status: Equatable {
        case stopped
        case starting(port: Int)
        case running(port: Int)
        case failed(String)
    }

    /// UserDefaults のキー(設定画面の @AppStorage と共通)
    static let enabledKey = "mcpServerEnabled"
    static let portKey = "mcpServerPort"
    static let defaultPort = 47821
    static let portRange = 1024...65535

    @Published private(set) var status: Status = .stopped

    /// 操作の対象。メインウィンドウが表示されたら結び付ける
    weak var editor: EditorViewModel?

    private var listener: MCPHTTPListener?
    /// 起動のたびに増やし、古い起動からの通知を無視する
    private var runID = 0

    static func endpointURL(port: Int) -> String {
        "http://127.0.0.1:\(port)\(MCPHTTPListener.endpointPath)"
    }

    /// Claude Code に登録するコマンド
    static func claudeCodeCommand(port: Int) -> String {
        "claude mcp add --transport http lccad \(endpointURL(port: port))"
    }

    /// テストの実行中(アプリがテストのホストとして起動している)か
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 設定に合わせて起動・停止する。テストの実行中は起動しない(ポートを開けない)
    func applySettings(_ defaults: UserDefaults = .standard) {
        let enabled = defaults.bool(forKey: Self.enabledKey)
        let port = defaults.object(forKey: Self.portKey) as? Int ?? Self.defaultPort
        if enabled, !Self.isRunningUnitTests {
            start(port: port)
        } else {
            stop()
        }
    }

    func start(port: Int) {
        switch status {
        case .running(let current), .starting(let current):
            if current == port { return }
        default:
            break
        }
        stop()
        guard Self.portRange.contains(port) else {
            status = .failed("The port must be between \(Self.portRange.lowerBound) and \(Self.portRange.upperBound)")
            return
        }

        runID += 1
        let id = runID
        status = .starting(port: port)

        let listener = MCPHTTPListener(
            handler: { [weak self] request in await Self.respond(to: request, controller: self) },
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event, runID: id) }
            }
        )
        self.listener = listener
        do {
            try listener.start(port: UInt16(port))
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// HTTP の要求 1 件ごとに、新しい `Server` と受け口を作って答え、答えたら止める。
    /// SDK の `Server` は 2 回目の `initialize` を断るので、1 つを使い続けると、最初に
    /// 接続したクライアントしか受け付けられない(#89)。受け口はステートレスで、
    /// 要求の間に持ち越す状態はない
    private nonisolated static func respond(
        to request: HTTPRequest, controller: MCPServerController?
    ) async -> HTTPResponse {
        let transport = StatelessHTTPServerTransport()
        let server = Server(
            name: "LCCAD",
            version: serverVersion,
            instructions: MCPToolCatalog.instructions,
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: MCPToolCatalog.tools)
        }
        await server.withMethodHandler(CallTool.self) { [weak controller] params in
            guard let controller else {
                return CallTool.Result(content: [.plainText("LCCAD is shutting down")], isError: true)
            }
            return await controller.callTool(params)
        }
        do {
            try await server.start(transport: transport)
        } catch {
            return .error(statusCode: 500, .internalError(error.localizedDescription))
        }
        let response = await transport.handleRequest(request)
        await server.stop()
        return response
    }

    private nonisolated static let serverVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    func stop() {
        runID += 1
        teardown()
        status = .stopped
    }

    private func handle(_ event: MCPHTTPListener.Event, runID id: Int) {
        guard runID == id else { return }
        switch event {
        case .ready(let port):
            status = .running(port: Int(port))
        case .failed(let message):
            fail(message)
        }
    }

    private func fail(_ message: String) {
        runID += 1
        teardown()
        status = .failed(message)
    }

    private func teardown() {
        listener?.stop()
        listener = nil
    }

    private func callTool(_ params: CallTool.Parameters) -> CallTool.Result {
        guard let editor else {
            return CallTool.Result(content: [.plainText("No LCCAD document window is open")], isError: true)
        }
        return MCPToolExecutor(editor: editor).call(params.name, arguments: params.arguments)
    }
}
