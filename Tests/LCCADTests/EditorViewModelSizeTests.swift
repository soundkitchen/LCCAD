import XCTest
@testable import LCCAD

@MainActor
final class EditorViewModelSizeTests: XCTestCase {

    private func makeEditor(shapes: [AnyShape]) -> EditorViewModel {
        var doc = DocumentData.empty()
        doc.layers[0].shapes = shapes
        let editor = EditorViewModel(document: doc)
        editor.undoManager = UndoManager()
        editor.selectedShapeIds = Set(shapes.map(\.id))
        return editor
    }

    // MARK: - Non-uniform editing (lock off)

    func testSetWidthOnlyChangesWidth() {
        let rect = RectangleShape(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 30, height: 40))
        let editor = makeEditor(shapes: [.rectangle(rect)])

        editor.setSelectedShapeSize(width: 60)

        guard case .rectangle(let resized) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected rectangle")
        }
        XCTAssertEqual(resized.size.width, 60, accuracy: 1e-9)
        XCTAssertEqual(resized.size.height, 40, accuracy: 1e-9, "height must not change with lock off")
        XCTAssertEqual(resized.origin.x, 10, accuracy: 1e-9, "bbox origin is the fixed anchor")
        XCTAssertEqual(resized.origin.y, 20, accuracy: 1e-9)
    }

    // MARK: - Aspect lock

    func testSetWidthWithAspectLockScalesHeightToo() {
        let rect = RectangleShape(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 30, height: 40))
        let editor = makeEditor(shapes: [.rectangle(rect)])
        editor.isSizeAspectLocked = true

        editor.setSelectedShapeSize(width: 60)

        guard case .rectangle(let resized) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected rectangle")
        }
        XCTAssertEqual(resized.size.width, 60, accuracy: 1e-9)
        XCTAssertEqual(resized.size.height, 80, accuracy: 1e-9, "lock keeps the aspect ratio")
    }

    // MARK: - Forced uniform scale

    func testArcSelectionForcesUniformScale() {
        let arc = ArcShape(center: CGPoint(x: 10, y: 10), radius: 5, startAngle: 0, endAngle: .pi)
        let editor = makeEditor(shapes: [.arc(arc)])

        XCTAssertTrue(editor.selectionRequiresUniformScale)

        // bbox is 10x10 (full-circle bounds); widening to 20 must scale uniformly.
        editor.setSelectedShapeSize(width: 20)
        guard case .arc(let resized) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected arc")
        }
        XCTAssertEqual(resized.radius, 10, accuracy: 1e-9, "arc must scale uniformly even with lock off")
    }

    func testRotatedRectangleForcesUniformScale() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10), rotation: .pi / 4)
        let editor = makeEditor(shapes: [.rectangle(rect)])
        XCTAssertTrue(editor.selectionRequiresUniformScale)
    }

    func testGroupContainingArcForcesUniformScale() {
        let arc = ArcShape(center: .zero, radius: 5, startAngle: 0, endAngle: .pi)
        let group = GroupShape(children: [.arc(arc)])
        let editor = makeEditor(shapes: [.group(group)])
        XCTAssertTrue(editor.selectionRequiresUniformScale)
    }

    func testPlainShapesDoNotForceUniformScale() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let line = LineShape(start: .zero, end: CGPoint(x: 5, y: 5))
        let editor = makeEditor(shapes: [.rectangle(rect), .line(line)])
        XCTAssertFalse(editor.selectionRequiresUniformScale)
    }

    // MARK: - Multi-selection

    func testMultiSelectionScalesAroundCombinedBBoxOrigin() {
        let r1 = RectangleShape(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 10, height: 10))
        let r2 = RectangleShape(origin: CGPoint(x: 20, y: 0), size: CGSize(width: 10, height: 10))
        let editor = makeEditor(shapes: [.rectangle(r1), .rectangle(r2)])

        // Combined bbox: 30x10 → widen to 60 (factor 2 in x).
        editor.setSelectedShapeSize(width: 60)

        guard case .rectangle(let s1) = editor.document.layers[0].shapes[0],
              case .rectangle(let s2) = editor.document.layers[0].shapes[1] else {
            return XCTFail("expected rectangles")
        }
        XCTAssertEqual(s1.origin.x, 0, accuracy: 1e-9)
        XCTAssertEqual(s1.size.width, 20, accuracy: 1e-9)
        XCTAssertEqual(s2.origin.x, 40, accuracy: 1e-9, "gap between shapes must scale too")
        XCTAssertEqual(s2.size.width, 20, accuracy: 1e-9)
        XCTAssertEqual(s1.size.height, 10, accuracy: 1e-9, "height untouched with lock off")
    }

    // MARK: - Guards

    func testZeroDimensionEditIsIgnored() {
        let line = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))  // height 0
        let editor = makeEditor(shapes: [.line(line)])

        editor.setSelectedShapeSize(height: 10)

        guard case .line(let unchanged) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected line")
        }
        XCTAssertEqual(unchanged.endPoint.x, 10, accuracy: 1e-9)
        XCTAssertEqual(unchanged.endPoint.y, 0, accuracy: 1e-9)
        XCTAssertFalse(editor.undoManager!.canUndo, "no-op must not register undo")
    }

    func testSameSizeCommitDoesNotRegisterUndo() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 30, height: 40))
        let editor = makeEditor(shapes: [.rectangle(rect)])

        editor.setSelectedShapeSize(width: 30)

        XCTAssertFalse(editor.undoManager!.canUndo)
    }

    // MARK: - Undo

    func testResizeSupportsUndoAndRedo() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 30, height: 40))
        let editor = makeEditor(shapes: [.rectangle(rect)])
        let undo = editor.undoManager!

        editor.setSelectedShapeSize(width: 60)
        XCTAssertTrue(undo.canUndo)

        undo.undo()
        guard case .rectangle(let reverted) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected rectangle")
        }
        XCTAssertEqual(reverted.size.width, 30, accuracy: 1e-9)

        undo.redo()
        guard case .rectangle(let redone) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected rectangle")
        }
        XCTAssertEqual(redone.size.width, 60, accuracy: 1e-9)
    }

    // MARK: - Stitch line follow-through

    func testResizeRegeneratesStitchHolesFromScaledGeometry() {
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 20, y: 0))
        let iron = PrickingIron.defaultDiamond
        let stitch = StitchLine(sourceShapeId: line.id, ironId: iron.id, mode: .fixedPitch)
        var doc = DocumentData.empty()
        doc.layers[0].shapes = [.line(line)]
        doc.layers[0].stitchLines = [stitch]
        doc.prickingIrons = [iron]
        let editor = EditorViewModel(document: doc)
        editor.undoManager = UndoManager()
        editor.selectedShapeIds = [line.id]

        editor.setSelectedShapeSize(width: 40)

        let holes = editor.document.layers[0].stitchLines[0].holes
        XCTAssertFalse(holes.isEmpty, "regeneration should produce holes")
        XCTAssertGreaterThan(holes.map(\.position.x).max() ?? 0, 20,
                             "holes must follow the widened line (pitch preserved, count adapts)")
        for hole in holes {
            XCTAssertEqual(hole.position.y, 0, accuracy: 0.01)
            XCTAssertLessThanOrEqual(hole.position.x, 40.01)
        }
    }
}
