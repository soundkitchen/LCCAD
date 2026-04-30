import XCTest
@testable import LCCAD

@MainActor
final class EditorViewModelUndoTests: XCTestCase {

    // MARK: - Page Layout Undo/Redo Chain

    func testUpdatePageLayoutSupportsUndoAndRedo() {
        let editor = EditorViewModel(document: .empty())
        let undo = UndoManager()
        editor.undoManager = undo

        let original = editor.document.settings.pageLayout.paperSize

        // Change paper size from default (A4) to A3
        editor.updatePageLayout(actionName: "Change Paper Size") { $0.paperSize = .a3 }
        XCTAssertEqual(editor.document.settings.pageLayout.paperSize, .a3)
        XCTAssertTrue(undo.canUndo)

        // Undo → should revert to original
        undo.undo()
        XCTAssertEqual(editor.document.settings.pageLayout.paperSize, original)
        XCTAssertTrue(undo.canRedo, "Redo must be available after undo")

        // Redo → should re-apply the change (this was the bug: redo was lost)
        undo.redo()
        XCTAssertEqual(editor.document.settings.pageLayout.paperSize, .a3,
                       "Redo must re-apply the paper size change")
    }

    func testUpdatePageLayoutMarginSurvivesUndoRedoRoundTrip() {
        let editor = EditorViewModel(document: .empty())
        let undo = UndoManager()
        editor.undoManager = undo

        let originalMargin = editor.document.settings.pageLayout.margin

        editor.updatePageLayout(actionName: "Edit Margin") { $0.margin = 15 }
        XCTAssertEqual(editor.document.settings.pageLayout.margin, 15)

        undo.undo()
        XCTAssertEqual(editor.document.settings.pageLayout.margin, originalMargin)

        undo.redo()
        XCTAssertEqual(editor.document.settings.pageLayout.margin, 15)
    }

    func testUpdatePageLayoutNoOpDoesNotRegisterUndo() {
        let editor = EditorViewModel(document: .empty())
        let undo = UndoManager()
        editor.undoManager = undo

        // Setting the same value should not create an undo entry
        let currentSize = editor.document.settings.pageLayout.paperSize
        editor.updatePageLayout(actionName: "Change Paper Size") { $0.paperSize = currentSize }
        XCTAssertFalse(undo.canUndo)
    }
}
