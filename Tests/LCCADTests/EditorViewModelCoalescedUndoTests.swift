import XCTest
@testable import LCCAD

/// 連続編集(内容欄の打鍵、カラーピッカーのドラッグ)を 1 件の Undo にまとめる挙動 (#72)
@MainActor
final class EditorViewModelCoalescedUndoTests: XCTestCase {

    private var editor: EditorViewModel!
    private var undo: UndoManager!
    private var textId: UUID!
    private var lineId: UUID!

    override func setUp() async throws {
        let text = TextShape(position: .zero, content: "")
        let line = LineShape(start: .zero, end: CGPoint(x: 50, y: 0))
        var doc = DocumentData.empty()
        doc.layers[0].shapes = [.text(text), .line(line)]
        editor = EditorViewModel(document: doc)
        undo = UndoManager()
        // 実アプリでは自動グルーピング(groupsByEvent)がイベント(打鍵・ドラッグ更新)ごとに
        // Undo グループを分ける。テスト環境ではイベントループがなく自動グループが閉じないため、
        // 自動グルーピングを切り、`event {}` で 1 イベントずつ手動のグループで囲む
        undo.groupsByEvent = false
        editor.undoManager = undo
        textId = text.id
        lineId = line.id
        editor.selectedShapeIds = [textId]
    }

    /// 1 イベント分の操作を 1 つの Undo グループで囲む
    private func event(_ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    /// ⌘Z 1 回分。手動グルーピングでは登録のないイベントも空のグループとして残るが、
    /// 実アプリの自動グルーピングは登録時にしかグループを作らないので、空のグループは読み飛ばす。
    /// document が変わったら true
    @discardableResult
    private func undoStep() -> Bool {
        let before = editor.document
        while undo.canUndo {
            undo.undo()
            if editor.document != before { return true }
        }
        return false
    }

    /// ⇧⌘Z 1 回分(空のグループの扱いは undoStep と同じ)
    @discardableResult
    private func redoStep() -> Bool {
        let before = editor.document
        while undo.canRedo {
            undo.redo()
            if editor.document != before { return true }
        }
        return false
    }

    private func type(_ content: String) {
        event { editor.updateTextProperty(coalescing: .textContent) { $0.content = content } }
    }

    private var text: TextShape? {
        guard case .text(let t) = editor.document.layers[0].shapes[0] else { return nil }
        return t
    }

    private var content: String? { text?.content }

    private var lineColor: CodableColor {
        editor.document.layers[0].shapes[1].stroke.color
    }

    private func color(_ r: CGFloat) -> CodableColor { CodableColor(r: r, g: 0, b: 0, a: 1) }

    // MARK: - 内容欄の打鍵

    func testConsecutiveTypingCoalescesIntoOneUndo() {
        type("H"); type("He"); type("Hel")
        XCTAssertEqual(content, "Hel")

        XCTAssertTrue(undoStep())
        XCTAssertEqual(content, "", "One undo must revert the whole typing burst")
        XCTAssertFalse(undoStep(), "The burst must be a single undo entry")

        XCTAssertTrue(redoStep())
        XCTAssertEqual(content, "Hel", "Redo must restore the full typed text")
    }

    func testEndCoalescedEditStartsNewUndo() {
        type("a"); type("ab")
        editor.endCoalescedEdit()   // フォーカスアウト
        type("abc")

        undoStep()
        XCTAssertEqual(content, "ab")
        undoStep()
        XCTAssertEqual(content, "")
    }

    func testOtherUndoableEditEndsCoalescing() {
        type("a")
        event { editor.updateTextProperty { $0.textAlignment = .center } }
        type("ab")

        undoStep()
        XCTAssertEqual(content, "a", "Typing after another edit must be its own undo entry")
        XCTAssertEqual(text?.textAlignment, .center)
        undoStep()
        XCTAssertEqual(text?.textAlignment, .left)
        undoStep()
        XCTAssertEqual(content, "")
    }

    func testSelectionChangeEndsCoalescing() {
        type("a")
        editor.selectedShapeIds = []
        editor.selectedShapeIds = [textId]
        type("ab")

        undoStep()
        XCTAssertEqual(content, "a", "Re-selecting the shape must start a new undo entry")
    }

    func testTypingAfterUndoStartsNewUndo() {
        type("a"); type("ab")
        undoStep()
        XCTAssertEqual(content, "")
        type("x")

        XCTAssertTrue(undoStep(), "Typing after undo must register its own entry")
        XCTAssertEqual(content, "")
    }

    func testNoOpFirstEditDoesNotSwallowLaterChange() {
        // 現在値と同じ内容での呼び出し(Undo 登録なし)をまとめの起点にしない
        type("")
        type("a")
        XCTAssertTrue(undoStep(), "A real change after a no-op must still register an undo entry")
        XCTAssertEqual(content, "")
    }

    // MARK: - カラーピッカーのドラッグ

    func testStrokeColorDragCoalescesUntilMouseUp() {
        editor.selectedShapeIds = [lineId]
        let original = lineColor
        for r in [0.2, 0.4, 0.6] {
            event { editor.updateStroke(coalescing: .strokeColor) { $0.color = color(r) } }
        }
        editor.endCoalescedEdit()   // マウスアップ
        event { editor.updateStroke(coalescing: .strokeColor) { $0.color = color(0.8) } }

        undoStep()
        XCTAssertEqual(lineColor, color(0.6))
        undoStep()
        XCTAssertEqual(lineColor, original, "One undo must revert the whole drag")
        XCTAssertFalse(undoStep())
    }

    func testTextColorDragCoalescesIntoOneUndo() {
        let originalColor = text?.stroke.color
        for r in [0.2, 0.4] {
            event { editor.updateTextProperty(coalescing: .textColor) { $0.stroke.color = color(r) } }
        }

        undoStep()
        XCTAssertEqual(text?.stroke.color, originalColor)
        XCTAssertFalse(undoStep())
    }

    func testDifferentCoalescedKindsAreSeparateUndos() {
        type("a")
        event { editor.updateTextProperty(coalescing: .textColor) { $0.stroke.color = color(0.5) } }

        undoStep()
        XCTAssertEqual(content, "a", "Color change must not merge into the typing entry")
        undoStep()
        XCTAssertEqual(content, "")
    }

    func testNonCoalescedEditsStillRegisterEachTime() {
        event { editor.updateTextProperty { $0.content = "a" } }
        event { editor.updateTextProperty { $0.content = "ab" } }

        undoStep()
        XCTAssertEqual(content, "a")
    }
}
