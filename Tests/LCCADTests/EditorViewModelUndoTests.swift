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

    // MARK: - Arc Property Undo/Redo

    func testUpdateArcPropertySupportsUndoAndRedo() {
        let arc = ArcShape(center: .zero, radius: 25, startAngle: 0, endAngle: .pi / 2)
        var doc = DocumentData.empty()
        doc.layers[0].shapes = [.arc(arc)]
        let editor = EditorViewModel(document: doc)
        let undo = UndoManager()
        editor.undoManager = undo
        editor.selectedShapeIds = [arc.id]

        editor.updateArcProperty { $0.radius = 40 }
        guard case .arc(let changed) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected arc")
        }
        XCTAssertEqual(changed.radius, 40)
        XCTAssertTrue(undo.canUndo)

        undo.undo()
        guard case .arc(let reverted) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected arc")
        }
        XCTAssertEqual(reverted.radius, 25)
        XCTAssertTrue(undo.canRedo)

        undo.redo()
        guard case .arc(let redone) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected arc")
        }
        XCTAssertEqual(redone.radius, 40)
    }

    func testUpdateArcPropertyNoOpDoesNotRegisterUndo() {
        let arc = ArcShape(center: .zero, radius: 25, startAngle: 0, endAngle: .pi / 2)
        var doc = DocumentData.empty()
        doc.layers[0].shapes = [.arc(arc)]
        let editor = EditorViewModel(document: doc)
        let undo = UndoManager()
        editor.undoManager = undo
        editor.selectedShapeIds = [arc.id]

        // 数値的に等価な打ち直し(例: "30.0" → "30")に相当する同値代入
        editor.updateArcProperty { $0.radius = 25 }
        XCTAssertFalse(undo.canUndo, "No-op arc edit must not register an undo entry")
    }

    // MARK: - Dimension Property Undo/Redo

    func testUpdateDimensionPropertySupportsUndoAndRedo() {
        let dim = DimensionLineShape(start: .zero, end: CGPoint(x: 50, y: 0), offset: 8)
        var doc = DocumentData.empty()
        doc.layers[0].shapes = [.dimensionLine(dim)]
        let editor = EditorViewModel(document: doc)
        let undo = UndoManager()
        editor.undoManager = undo
        editor.selectedShapeIds = [dim.id]

        editor.updateDimensionProperty { $0.offset = 12 }
        guard case .dimensionLine(let changed) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected dimension line")
        }
        XCTAssertEqual(changed.offset, 12)
        XCTAssertTrue(undo.canUndo)

        undo.undo()
        guard case .dimensionLine(let reverted) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected dimension line")
        }
        XCTAssertEqual(reverted.offset, 8)
        XCTAssertTrue(undo.canRedo)

        undo.redo()
        guard case .dimensionLine(let redone) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected dimension line")
        }
        XCTAssertEqual(redone.offset, 12)
    }

    func testUpdateDimensionPropertyNoOpDoesNotRegisterUndo() {
        let dim = DimensionLineShape(start: .zero, end: CGPoint(x: 50, y: 0), offset: 8)
        var doc = DocumentData.empty()
        doc.layers[0].shapes = [.dimensionLine(dim)]
        let editor = EditorViewModel(document: doc)
        let undo = UndoManager()
        editor.undoManager = undo
        editor.selectedShapeIds = [dim.id]

        editor.updateDimensionProperty { $0.offset = 8 }
        XCTAssertFalse(undo.canUndo, "No-op dimension edit must not register an undo entry")
    }
}
