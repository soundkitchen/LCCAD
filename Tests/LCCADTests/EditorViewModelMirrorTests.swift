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

    // MARK: - Mirror Down (Copy) flush placement

    /// Mirror Down (Copy) on a Rectangle: the copy's top edge must coincide with
    /// the original's bottom edge (no gap, no overlap).
    func testMirrorCopyDownRectangleIsFlush() {
        let rect = RectangleShape(origin: CGPoint(x: 10, y: 10), size: CGSize(width: 50, height: 30))
        let editor = makeEditor(shapes: [.rectangle(rect)])
        editor.selectedShapeIds = [rect.id]

        editor.mirrorSelectedShapes(.horizontal, copy: true)

        XCTAssertEqual(editor.document.layers[0].shapes.count, 2)
        guard case .rectangle(let copied) = editor.document.layers[0].shapes[1] else {
            return XCTFail("expected mirrored rectangle at index 1")
        }
        // Original bottom edge is at y = 10 + 30 = 40. Copy must start at y = 40.
        XCTAssertEqual(copied.origin.y, 40, accuracy: 1e-9, "copy top edge must equal original bottom edge")
        XCTAssertEqual(copied.origin.x, 10, accuracy: 1e-9)
        XCTAssertEqual(copied.size.width, 50, accuracy: 1e-9)
        XCTAssertEqual(copied.size.height, 30, accuracy: 1e-9)
    }

    /// Mirror Down (Copy) on an Ellipse: the copy's top must equal the original's bottom.
    func testMirrorCopyDownEllipseIsFlush() {
        let ellipse = EllipseShape(center: CGPoint(x: 50, y: 50), radiusX: 20, radiusY: 10)
        let editor = makeEditor(shapes: [.ellipse(ellipse)])
        editor.selectedShapeIds = [ellipse.id]

        editor.mirrorSelectedShapes(.horizontal, copy: true)

        guard case .ellipse(let copied) = editor.document.layers[0].shapes[1] else {
            return XCTFail("expected mirrored ellipse at index 1")
        }
        // Original bottom = 50 + 10 = 60. Copy center must be at y = 60 + 10 = 70.
        XCTAssertEqual(copied.center.y, 70, accuracy: 1e-9)
        XCTAssertEqual(copied.center.x, 50, accuracy: 1e-9)
    }

    /// Mirror Down (Copy) on an Arc that spans only the upper half of its circle.
    /// The arc's *visual* bottom is at y = center.y (not center.y + radius).
    /// The copy's visual top must equal the original's visual bottom.
    func testMirrorCopyDownArcUsesVisualExtent() {
        // Upper half-circle: center=(50,50), radius=20, angle from π to 2π (counter-clockwise).
        // sin(π) = 0, sin(2π) = 0, so the arc traces y from 50 down to 50-20=30 and back.
        // Visual bbox: y ∈ [30, 50], not [30, 70] (which is the full circle bbox).
        let arc = ArcShape(
            center: CGPoint(x: 50, y: 50), radius: 20,
            startAngle: .pi, endAngle: 2 * .pi, clockwise: false
        )
        let editor = makeEditor(shapes: [.arc(arc)])
        editor.selectedShapeIds = [arc.id]

        editor.mirrorSelectedShapes(.horizontal, copy: true)

        guard case .arc(let copied) = editor.document.layers[0].shapes[1] else {
            return XCTFail("expected mirrored arc at index 1")
        }
        // Original visual bottom = 50. Copy must be reflected across y = 50,
        // putting its center at y = 50 (so its visual top, which mirrors to the arc's
        // visual bottom, sits at y = 50 — flush with the original).
        XCTAssertEqual(copied.center.y, 50, accuracy: 1e-9, "arc copy must use visual extent (y=50), not full-circle bbox.maxY")
        XCTAssertEqual(copied.center.x, 50, accuracy: 1e-9)
    }

    /// Mirror Down (Copy) on a Bezier whose control handles extend below the visible curve.
    /// The copy must sit flush against the visible curve, not against the handle bbox.
    func testMirrorCopyDownBezierUsesVisualExtent() {
        // Two anchors at y = 0 with both controlOut/controlIn handles at y = 50.
        // The actual curve stays in y ∈ [0, ~37.5] (cubic at t=0.5 with both controls at 50
        // gives y = 3*0.25*0.5*50 + 3*0.5*0.25*50 = 18.75 + 18.75 = 37.5).
        // boundingBox (with handles) gives maxY = 50; visualBoundingBox should give maxY = 37.5.
        let p0 = BezierPoint(point: CGPoint(x: 0, y: 0), controlIn: CGPoint(x: 0, y: 0), controlOut: CGPoint(x: 30, y: 50))
        let p1 = BezierPoint(point: CGPoint(x: 100, y: 0), controlIn: CGPoint(x: 70, y: 50), controlOut: CGPoint(x: 100, y: 0))
        let bezier = BezierShape(points: [p0, p1], isClosed: false)
        let editor = makeEditor(shapes: [.bezier(bezier)])
        editor.selectedShapeIds = [bezier.id]

        editor.mirrorSelectedShapes(.horizontal, copy: true)

        guard case .bezier(let copied) = editor.document.layers[0].shapes[1] else {
            return XCTFail("expected mirrored bezier at index 1")
        }
        // Original curve's visual bottom is 37.5 (at t=0.5). Copy's anchors at y=0 must
        // mirror to y = 75 (= 2 * 37.5). controlOut/In at y=50 must mirror to y = 25.
        XCTAssertEqual(copied.points[0].point.y, 75, accuracy: 1e-6, "anchor must mirror across visual extent (y=37.5)")
        XCTAssertEqual(copied.points[0].controlOut.y, 25, accuracy: 1e-6)
        XCTAssertEqual(copied.points[1].point.y, 75, accuracy: 1e-6)
        XCTAssertEqual(copied.points[1].controlIn.y, 25, accuracy: 1e-6)
    }

    /// Mirror Right (Copy) on the same Bezier — the right edge of the visual curve
    /// happens to coincide with the bbox maxX (anchor at x=100), so copy is flush
    /// regardless of whether we use boundingBox or visualBoundingBox. This is the
    /// "right works fine" case the user reported.
    func testMirrorCopyRightBezierIsFlush() {
        let p0 = BezierPoint(point: CGPoint(x: 0, y: 0), controlIn: CGPoint(x: 0, y: 0), controlOut: CGPoint(x: 30, y: 50))
        let p1 = BezierPoint(point: CGPoint(x: 100, y: 0), controlIn: CGPoint(x: 70, y: 50), controlOut: CGPoint(x: 100, y: 0))
        let bezier = BezierShape(points: [p0, p1], isClosed: false)
        let editor = makeEditor(shapes: [.bezier(bezier)])
        editor.selectedShapeIds = [bezier.id]

        editor.mirrorSelectedShapes(.vertical, copy: true)

        guard case .bezier(let copied) = editor.document.layers[0].shapes[1] else {
            return XCTFail("expected mirrored bezier at index 1")
        }
        // Visual right edge = 100. Anchor at x=0 mirrors to x=200, anchor at x=100 stays.
        XCTAssertEqual(copied.points[0].point.x, 200, accuracy: 1e-6)
        XCTAssertEqual(copied.points[1].point.x, 100, accuracy: 1e-6)
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
        // The original stitch line keeps its source shape; the copy points to the new shape.
        let copySourceIds = Set(editor.document.layers[0].stitchLines.flatMap(\.sourceShapeIds))
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
