import XCTest
@testable import LCCAD

@MainActor
final class EditorViewModelMirrorTests: XCTestCase {

    private func makeEditor(shapes: [AnyShape], stitchLines: [StitchLine] = []) -> EditorViewModel {
        var doc = DocumentData.empty()
        doc.layers[0].shapes = shapes
        doc.layers[0].stitchLines = stitchLines
        let editor = EditorViewModel(document: doc)
        editor.undoManager = UndoManager()
        return editor
    }

    // MARK: - In-place mirror

    func testMirrorVerticalInPlaceUsesSelectionCenter() {
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0))
        let editor = makeEditor(shapes: [.line(line)])
        editor.selectedShapeIds = [line.id]

        editor.mirrorSelectedShapes(.vertical, copy: false)

        guard case .line(let l) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected line")
        }
        // bbox = (0,0,10,0), midX = 5. Reflecting (0,0) across x=5 → (10,0). (10,0) → (0,0).
        XCTAssertEqual(l.startPoint.x, 10, accuracy: 1e-9)
        XCTAssertEqual(l.endPoint.x, 0, accuracy: 1e-9)
        XCTAssertEqual(editor.document.layers[0].shapes.count, 1, "in-place should not duplicate")
    }

    func testMirrorHorizontalInPlace() {
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 10))
        let editor = makeEditor(shapes: [.line(line)])
        editor.selectedShapeIds = [line.id]

        editor.mirrorSelectedShapes(.horizontal, copy: false)

        guard case .line(let l) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected line")
        }
        XCTAssertEqual(l.startPoint.y, 10, accuracy: 1e-9)
        XCTAssertEqual(l.endPoint.y, 0, accuracy: 1e-9)
    }

    func testMirrorMultipleShapesUsesCombinedBBoxCenter() {
        let dotA = DotShape(position: CGPoint(x: 0, y: 0))
        let dotB = DotShape(position: CGPoint(x: 10, y: 0))
        let editor = makeEditor(shapes: [.dot(dotA), .dot(dotB)])
        editor.selectedShapeIds = [dotA.id, dotB.id]

        editor.mirrorSelectedShapes(.vertical, copy: false)

        // Dots have radius 1.5 by default → bbox of dotA = (-1.5, -1.5, 3, 3), of dotB = (8.5, -1.5, 3, 3)
        // Combined bbox midX = 5.0. (0,0) → (10,0). (10,0) → (0,0). Positions swap.
        let positions = editor.document.layers[0].shapes.compactMap { shape -> CGPoint? in
            if case .dot(let d) = shape { return d.position }
            return nil
        }
        let xs = positions.map(\.x).sorted()
        XCTAssertEqual(xs.count, 2)
        XCTAssertEqual(xs[0], 0, accuracy: 1e-9)
        XCTAssertEqual(xs[1], 10, accuracy: 1e-9)
    }

    // MARK: - Copy mirror

    func testMirrorCopyVerticalAddsAdjacentDuplicate() {
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0))
        let editor = makeEditor(shapes: [.line(line)])
        editor.selectedShapeIds = [line.id]

        editor.mirrorSelectedShapes(.vertical, copy: true)

        XCTAssertEqual(editor.document.layers[0].shapes.count, 2, "copy mode should duplicate")
        // First entry is unchanged original
        guard case .line(let original) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected line at index 0")
        }
        XCTAssertEqual(original.startPoint, .zero)
        XCTAssertEqual(original.endPoint, CGPoint(x: 10, y: 0))

        // Second entry is the mirrored clone, axis at bbox.maxX = 10
        guard case .line(let copied) = editor.document.layers[0].shapes[1] else {
            return XCTFail("expected mirrored copy at index 1")
        }
        // Reflecting (0,0) across x=10 → (20,0). (10,0) across x=10 → (10,0).
        XCTAssertEqual(copied.startPoint.x, 20, accuracy: 1e-9)
        XCTAssertEqual(copied.endPoint.x, 10, accuracy: 1e-9)
    }

    func testMirrorCopyAssignsFreshIds() {
        let line = LineShape(start: .zero, end: CGPoint(x: 5, y: 0))
        let editor = makeEditor(shapes: [.line(line)])
        editor.selectedShapeIds = [line.id]

        editor.mirrorSelectedShapes(.vertical, copy: true)

        let ids = editor.document.layers[0].shapes.map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids[0], ids[1], "copy must use a new UUID")
    }

    func testMirrorCopySwitchesSelectionToClone() {
        let line = LineShape(start: .zero, end: CGPoint(x: 5, y: 0))
        let editor = makeEditor(shapes: [.line(line)])
        editor.selectedShapeIds = [line.id]

        editor.mirrorSelectedShapes(.vertical, copy: true)

        let copyId = editor.document.layers[0].shapes[1].id
        XCTAssertEqual(editor.selectedShapeIds, [copyId])
    }

    func testMirrorCopyClonesGroupRecursivelyWithFreshIds() {
        let dot = DotShape(position: CGPoint(x: 1, y: 1))
        let group = GroupShape(children: [.dot(dot)])
        let editor = makeEditor(shapes: [.group(group)])
        editor.selectedShapeIds = [group.id]

        editor.mirrorSelectedShapes(.vertical, copy: true)

        guard case .group(let originalGroup) = editor.document.layers[0].shapes[0],
              case .group(let copiedGroup) = editor.document.layers[0].shapes[1] else {
            return XCTFail("expected two groups")
        }
        XCTAssertNotEqual(originalGroup.id, copiedGroup.id)
        guard case .dot(let originalDot) = originalGroup.children[0],
              case .dot(let copiedDot) = copiedGroup.children[0] else {
            return XCTFail("expected dots inside groups")
        }
        XCTAssertNotEqual(originalDot.id, copiedDot.id, "child UUIDs must be regenerated")
    }

    // MARK: - Stitch line follow-through

    func testInPlaceMirrorRegeneratesStitchLines() {
        // Build a line + iron + stitch line so AutoStitchEngine has something to walk.
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

        editor.mirrorSelectedShapes(.vertical, copy: false)

        // After regenerate, holes should sit on the (still 0..20 span) line; non-empty.
        let holes = editor.document.layers[0].stitchLines[0].holes
        XCTAssertFalse(holes.isEmpty, "regeneration should produce holes")
        for hole in holes {
            XCTAssertEqual(hole.position.y, 0, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(hole.position.x, -0.01)
            XCTAssertLessThanOrEqual(hole.position.x, 20.01)
        }
    }

    func testCopyMirrorDuplicatesStitchLines() {
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

        editor.mirrorSelectedShapes(.vertical, copy: true)

        XCTAssertEqual(editor.document.layers[0].stitchLines.count, 2, "stitch lines should duplicate")
        // The original stitch line keeps its sourceShapeId; the copy points to the new shape.
        let copySourceIds = Set(editor.document.layers[0].stitchLines.map(\.sourceShapeId))
        let shapeIds = Set(editor.document.layers[0].shapes.map(\.id))
        XCTAssertEqual(copySourceIds, shapeIds, "every stitch line must reference an existing shape")
    }

    // MARK: - Undo / Redo

    func testInPlaceMirrorUndoRestoresOriginal() {
        let line = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))
        let editor = makeEditor(shapes: [.line(line)])
        editor.selectedShapeIds = [line.id]
        let snapshot = editor.document

        editor.mirrorSelectedShapes(.vertical, copy: false)
        XCTAssertNotEqual(editor.document, snapshot)

        editor.undoManager?.undo()
        XCTAssertEqual(editor.document, snapshot)

        editor.undoManager?.redo()
        XCTAssertNotEqual(editor.document, snapshot)
    }

    func testCopyMirrorUndoRemovesClone() {
        let line = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))
        let editor = makeEditor(shapes: [.line(line)])
        editor.selectedShapeIds = [line.id]

        editor.mirrorSelectedShapes(.vertical, copy: true)
        XCTAssertEqual(editor.document.layers[0].shapes.count, 2)

        editor.undoManager?.undo()
        XCTAssertEqual(editor.document.layers[0].shapes.count, 1)
    }

    // MARK: - Empty selection

    func testMirrorWithoutSelectionIsNoOp() {
        let line = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))
        let editor = makeEditor(shapes: [.line(line)])
        // selectedShapeIds left empty
        let snapshot = editor.document

        editor.mirrorSelectedShapes(.vertical, copy: false)
        XCTAssertEqual(editor.document, snapshot)
        XCTAssertFalse(editor.undoManager?.canUndo ?? true)
    }
}
