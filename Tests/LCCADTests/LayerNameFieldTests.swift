import AppKit
import XCTest
@testable import LCCAD

/// レイヤー名の入力欄 (#95, review #97)。本物のウィンドウに載せて、フィールドエディタとの配線を確かめる
@MainActor
final class LayerNameFieldTests: XCTestCase {

    /// キャンバスの代わり。クリックでファーストレスポンダーになる NSView
    private final class FocusableView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    private var window: NSWindow!
    private var canvas: FocusableView!
    private var field: LayerNameTextField!
    private var coordinator: LayerNameField.Coordinator!
    private var committed: [String] = []
    private var cancelCount = 0

    override func setUp() async throws {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 60),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        canvas = FocusableView(frame: NSRect(x: 0, y: 40, width: 240, height: 20))
        window.contentView?.addSubview(canvas)
        XCTAssertTrue(window.makeFirstResponder(canvas), "編集前はキャンバスにフォーカスがある")
        field = LayerNameTextField(frame: NSRect(x: 10, y: 10, width: 200, height: 22))
        field.stringValue = "Layer 1"
        field.isEditable = true
        window.contentView?.addSubview(field)

        committed = []
        cancelCount = 0
        let parent = LayerNameField(
            initialName: "Layer 1",
            onCommit: { [unowned self] in committed.append($0) },
            onCancel: { [unowned self] in cancelCount += 1 })
        coordinator = LayerNameField.Coordinator(parent)
        coordinator.field = field
        field.delegate = coordinator
        // ウィンドウに載せた後に結ぶ(載せたときの非同期のフォーカス移動は使わず、beginEditing() を直接呼ぶ)
        field.coordinator = coordinator
        coordinator.beginEditing()
        XCTAssertNotNil(field.currentEditor(), "欄にフォーカスが移る")
    }

    override func tearDown() async throws {
        coordinator.tearDown()
        window.close()
    }

    private func fieldEditor() throws -> NSTextView {
        try XCTUnwrap(field.currentEditor() as? NSTextView)
    }

    /// 入力の Undo は欄だけの UndoManager に積まれ、⌘Z(undo:)は欄が受け止める
    func testTypingUndoStaysInTheField() throws {
        let editor = try fieldEditor()
        XCTAssertTrue(editor.undoManager === field.fieldUndoManager)

        editor.selectAll(nil)
        editor.insertText("裁断線", replacementRange: editor.selectedRange())
        XCTAssertEqual(editor.string, "裁断線")
        XCTAssertTrue(field.fieldUndoManager.canUndo)
        XCTAssertFalse(window.undoManager?.canUndo ?? false, "ウィンドウ(document)の UndoManager には積まない")

        // レスポンダーチェーンで undo: を最初に受け止めるのは欄(ウィンドウまで流れない)
        var responder: NSResponder? = editor
        let undoAction = #selector(LayerNameTextField.undo(_:))
        while let current = responder, !current.responds(to: undoAction) {
            responder = current.nextResponder
        }
        XCTAssertTrue(responder === field)

        field.undo(nil)
        XCTAssertEqual(editor.string, "Layer 1")
    }

    /// 欄の外のクリックなどで確定するとき、IME の未確定文字も含めて確定する
    func testCommitIncludesMarkedText() throws {
        let editor = try fieldEditor()
        editor.selectAll(nil)
        editor.setMarkedText("さいだんせん", selectedRange: NSRange(location: 6, length: 0),
                             replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())

        coordinator.finish(commit: true)
        XCTAssertEqual(committed, ["さいだんせん"])
        XCTAssertIdentical(window.firstResponder, canvas, "フォーカスは編集前のキャンバスに戻る")
        XCTAssertEqual(cancelCount, 0)
    }

    /// Enter で 1 回だけ確定する(フォーカスを外したときの textDidEndEditing では重ねて確定しない)
    func testEnterCommitsOnce() throws {
        let editor = try fieldEditor()
        editor.selectAll(nil)
        editor.insertText("ステッチ", replacementRange: editor.selectedRange())

        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(committed, ["ステッチ"])
        XCTAssertIdentical(window.firstResponder, canvas, "フォーカスは編集前のキャンバスに戻る")

        coordinator.finish(commit: true)
        XCTAssertEqual(committed, ["ステッチ"], "2 回目は何もしない")
    }

    /// Escape で取り消す。確定は伝えない
    func testEscapeCancels() throws {
        let editor = try fieldEditor()
        editor.selectAll(nil)
        editor.insertText("刻印", replacementRange: editor.selectedRange())

        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(cancelCount, 1)
        XCTAssertTrue(committed.isEmpty)
        XCTAssertIdentical(window.firstResponder, canvas, "フォーカスは編集前のキャンバスに戻る")
    }

    /// 編集前のファーストレスポンダーがウィンドウから外れていたら、ウィンドウに戻す
    func testFocusFallsBackToWindowWhenPreviousResponderIsGone() throws {
        canvas.removeFromSuperview()
        coordinator.finish(commit: true)
        XCTAssertIdentical(window.firstResponder, window)
    }

    /// Tab などでフォーカスが外れたときも確定する
    func testLosingFocusCommits() throws {
        let editor = try fieldEditor()
        editor.selectAll(nil)
        editor.insertText("型紙", replacementRange: editor.selectedRange())

        window.makeFirstResponder(nil)
        XCTAssertEqual(committed, ["型紙"])
    }
}
