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

    private var server: Server?
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

        let transport = StatelessHTTPServerTransport()
        let server = Server(
            name: "LCCAD",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            instructions: MCPToolCatalog.instructions,
            capabilities: .init(tools: .init(listChanged: false))
        )
        let listener = MCPHTTPListener(
            handler: { request in await transport.handleRequest(request) },
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event, runID: id) }
            }
        )
        self.server = server
        self.listener = listener

        Task {
            await server.withMethodHandler(ListTools.self) { _ in
                ListTools.Result(tools: MCPToolCatalog.tools)
            }
            await server.withMethodHandler(CallTool.self) { [weak self] params in
                guard let self else {
                    return CallTool.Result(content: [.plainText("LCCAD is shutting down")], isError: true)
                }
                return await self.callTool(params)
            }
            do {
                try await server.start(transport: transport)
                guard runID == id else { return }
                try listener.start(port: UInt16(port))
            } catch {
                guard runID == id else { return }
                fail(error.localizedDescription)
            }
        }
    }

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
        if let server {
            Task { await server.stop() }
        }
        server = nil
    }

    private func callTool(_ params: CallTool.Parameters) -> CallTool.Result {
        guard let editor else {
            return CallTool.Result(content: [.plainText("No LCCAD document window is open")], isError: true)
        }
        return MCPToolExecutor(editor: editor).call(params.name, arguments: params.arguments)
    }
}
