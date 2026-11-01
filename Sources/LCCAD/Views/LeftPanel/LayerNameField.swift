import AppKit
import SwiftUI

// MARK: - レイヤー名の入力欄 (#95)
//
// レイヤーリストで名前をその場で編集する 1 行の入力欄。SwiftUI の TextField ではなく
// NSTextField を包む。理由は次のとおり(review #97):
//
// - 入力の Undo を欄の中に閉じ込める(Finder の名前変更と同じ)。TextField の中のフィールドエディタは
//   入力の Undo をウィンドウの UndoManager(= document の UndoManager)に登録するので、
//   document の Undo と混ざる。何も打たずに ⌘Z を押すと document の Undo が走り、直前が
//   「Add Layer」なら編集中のレイヤーそのものが消える。この欄は入力の Undo を欄だけの
//   UndoManager に積み、⌘Z / ⇧⌘Z の `undo:` / `redo:` もそこで受け止める(`LayerNameTextField`)。
//   編集中は document の Undo に届かない
// - 欄の外のクリックで確定するときに、IME の未確定文字も含めて確定する。パネルの空きスペースなど
//   フォーカスを取らない場所をクリックしても欄はフォーカスを手放さない(macOS の挙動)ので、
//   編集中だけ NSEvent のローカルモニターでマウスダウンを拾う。確定する文字列はフィールドエディタの
//   文字列(未確定文字を含む)から読む
//
// Enter・欄の外のクリック・フォーカスが外れたとき(Tab など)で確定し、Escape で取り消す。
// 確定・取り消しはどちらか 1 回だけ親に伝える。Enter・Escape・欄の外のクリック(同じアプリの
// 別のウィンドウのクリックを含む。マウスダウンはウィンドウが切り替わる前にモニターに届く)で
// 終えたときは、欄のウィンドウのフォーカスをキャンバスに移す(キャンバスの 1 文字のショートカットが
// すぐ効くように)。Tab など、先にフォーカスがほかへ移ったときは、その移動に任せる。

struct LayerNameField: NSViewRepresentable {
    let initialName: String
    var fontSize: CGFloat = 11
    /// 文字列が変わるたびに呼ばれる(未確定文字を含む)。親が下書きを持つため
    var onChange: (String) -> Void = { _ in }
    /// 編集を終えたときにフォーカスを移すビュー(キャンバス)。nil ならウィンドウに移す
    var focusAfterEditing: () -> NSView? = { nil }
    /// 確定した文字列(前後の空白は取り除いていない)
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> LayerNameTextField {
        let field = LayerNameTextField(frame: .zero)
        field.stringValue = initialName
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = .labelColor
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.usesSingleLineMode = true
        // 行の幅いっぱいに広げる(文字列の長さで幅を決めない)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.coordinator = context.coordinator
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: LayerNameTextField, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ field: LayerNameTextField, coordinator: Coordinator) {
        // 親が編集状態を解いて取り除いた(確定・取り消し・レイヤーが消えた)ので、もう何も伝えない
        coordinator.tearDown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LayerNameField
        weak var field: LayerNameTextField?
        private var isFinished = false
        private var mouseDownMonitor: Any?

        init(_ parent: LayerNameField) {
            self.parent = parent
        }

        /// 欄がウィンドウに載ったら、フォーカスを移して全選択し、欄の外のクリックの監視を始める
        func fieldDidMoveToWindow() {
            guard let field, field.window != nil, !isFinished else { return }
            // 右クリックメニューから始めたときは、メニューが閉じてからでないと
            // フォーカスが移らないことがあるので、次のループで移す
            DispatchQueue.main.async { [weak self] in
                self?.beginEditing()
            }
        }

        /// 欄にフォーカスを移して全選択し、欄の外のクリックの監視を始める
        /// - Parameter installsMouseDownMonitor: テストでは false にして、本物のクリックで確定しないようにする
        func beginEditing(installsMouseDownMonitor: Bool = true) {
            guard let field, let window = field.window, !isFinished else { return }
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
            if installsMouseDownMonitor { self.installMouseDownMonitor() }
        }

        /// 編集を終えたときにフォーカスを移す先。親が渡すキャンバスのビュー(同じウィンドウにあるときだけ)、
        /// なければ nil(ウィンドウ)。
        /// キャンバスの 1 文字のツール切り替えなどは、キャンバスがファーストレスポンダーのときだけ効く。
        /// 編集前のファーストレスポンダーに戻すだけでは、Properties の入力欄で値を確定した直後
        /// (SwiftUI の入力欄は Enter の後もフォーカスを持ったまま)に名前を編集したときなどに
        /// キャンバスへ戻らないので、キャンバスに移す
        private func responderAfterEditing(in window: NSWindow) -> NSResponder? {
            guard let view = parent.focusAfterEditing(), view.window === window else { return nil }
            return view
        }

        private func installMouseDownMonitor() {
            guard mouseDownMonitor == nil else { return }
            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                // ローカルモニターはメインスレッドで呼ばれる
                MainActor.assumeIsolated {
                    guard let self, !self.isInField(event) else { return }
                    self.finish(commit: true)
                }
                // イベントは消費しない。クリックした先の操作はそのまま行われる
                return event
            }
        }

        private func removeMouseDownMonitor() {
            if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
            mouseDownMonitor = nil
        }

        /// マウスダウンがこの欄の上か(欄の中のクリックはカーソル移動や単語選択に使う)
        private func isInField(_ event: NSEvent) -> Bool {
            guard let field, event.window === field.window else { return false }
            return field.bounds.contains(field.convert(event.locationInWindow, from: nil))
        }

        /// 編集を終え、確定なら文字列を、取り消しならそれだけを親に伝える。2 回目以降は何もしない
        func finish(commit: Bool) {
            guard !isFinished else { return }
            isFinished = true
            removeMouseDownMonitor()
            let fieldEditor = field?.currentEditor() as? NSTextView
            if let fieldEditor, fieldEditor.hasMarkedText() {
                // 未確定文字は、確定なら今の状態のまま受け入れ、取り消しなら捨てる
                if commit {
                    fieldEditor.unmarkText()
                } else {
                    fieldEditor.inputContext?.discardMarkedText()
                }
            }
            let text = fieldEditor?.string ?? field?.stringValue ?? ""
            // まだ欄にフォーカスがあれば(Enter・Escape・欄の外のクリック)、キャンバスに移す。
            // Tab などで先にフォーカスが移っていれば、その移動に任せる。
            // ここから textDidEndEditing が呼ばれても、終えた後なので何もしない
            if let field, let window = field.window, let fieldEditor, window.firstResponder === fieldEditor {
                window.makeFirstResponder(responderAfterEditing(in: window))
            }
            if commit {
                parent.onCommit(text)
            } else {
                parent.onCancel()
            }
        }

        func tearDown() {
            isFinished = true
            removeMouseDownMonitor()
        }

        // MARK: NSTextFieldDelegate

        func controlTextDidChange(_ notification: Notification) {
            guard let fieldEditor = field?.currentEditor() as? NSTextView else { return }
            parent.onChange(fieldEditor.string)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                finish(commit: true)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finish(commit: false)
                return true
            default:
                return false
            }
        }
    }
}

/// レイヤー名の入力欄の NSTextField。入力の Undo を欄だけの UndoManager で扱う。
///
/// 編集中のフィールドエディタは、delegate がこの欄で、レスポンダーチェーンでもすぐ次がこの欄になる。
/// そのため、どのフィールドエディタが使われても(ウィンドウ共有のものでも)次のように働く:
/// - 入力の Undo は `undoManagerForTextView:` が返す欄だけの UndoManager に積まれる
/// - ⌘Z / ⇧⌘Z の `undo:` / `redo:` はこの欄が受け止め、ウィンドウ(= document の Undo)へ流さない
final class LayerNameTextField: NSTextField, NSMenuItemValidation {
    weak var coordinator: LayerNameField.Coordinator?
    /// 欄だけの UndoManager。欄は編集のたびに作り直すので、履歴もその編集の間だけ
    let fieldUndoManager = UndoManager()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.fieldDidMoveToWindow()
    }

    /// Tab などでフォーカスが外れたときも確定する(Enter・Escape・欄の外のクリックは、
    /// その前に Coordinator が終えているので、ここでは何もしない)
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        coordinator?.finish(commit: true)
    }

    @objc(undoManagerForTextView:)
    func undoManager(for view: NSTextView) -> UndoManager? {
        fieldUndoManager
    }

    @objc func undo(_ sender: Any?) {
        if fieldUndoManager.canUndo { fieldUndoManager.undo() }
    }

    @objc func redo(_ sender: Any?) {
        if fieldUndoManager.canRedo { fieldUndoManager.redo() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)):
            return fieldUndoManager.canUndo
        case #selector(redo(_:)):
            return fieldUndoManager.canRedo
        default:
            return true
        }
    }
}
