import XCTest
import CoreGraphics
@testable import LCCAD

/// Tests for corner beveling: the `BevelTool` geometry primitives and the
/// `EditorViewModel` bulk (range-selection) operation (Issue #26).
final class BevelToolTests: XCTestCase {

    private func assertPoint(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat,
                             accuracy: CGFloat = 1e-4, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: accuracy, "x \(message)", file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: accuracy, "y \(message)", file: file, line: line)
    }

    // MARK: - filletCorner geometry

    func testFilletCorner90Degrees() {
        // Legs along +x and +y from the origin, radius 10.
        let fillet = BevelTool.filletCorner(prev: CGPoint(x: 100, y: 0),
                                            corner: .zero,
                                            next: CGPoint(x: 0, y: 100),
                                            radius: 10)
        let f = try! XCTUnwrap(fillet)
        assertPoint(f.tangentPrev, 10, 0, "tangent on +x leg")
        assertPoint(f.tangentNext, 0, 10, "tangent on +y leg")
        assertPoint(f.center, 10, 10, "center on the bisector")
        XCTAssertEqual(f.radius, 10, accuracy: 1e-4)
        // Both tangent points lie exactly `radius` from the center.
        XCTAssertEqual(f.center.distance(to: f.tangentPrev), 10, accuracy: 1e-4)
        XCTAssertEqual(f.center.distance(to: f.tangentNext), 10, accuracy: 1e-4)
    }

    func testFilletCornerNilWhenParallel() {
        // Both legs point the same way → no corner.
        XCTAssertNil(BevelTool.filletCorner(prev: CGPoint(x: 100, y: 0),
                                            corner: .zero,
                                            next: CGPoint(x: 50, y: 0),
                                            radius: 5))
    }

    func testFilletCornerNilWhenRadiusTooLarge() {
        // A radius needing a 100mm tangent distance cannot fit a 10mm leg.
        XCTAssertNil(BevelTool.filletCorner(prev: CGPoint(x: 10, y: 0),
                                            corner: .zero,
                                            next: CGPoint(x: 0, y: 10),
                                            radius: 100))
    }

    // MARK: - bevel(line1:line2:) regression

    func testBevelTwoLinesSharedEndpoint() {
        let a = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        let b = LineShape(start: CGPoint(x: 100, y: 0), end: CGPoint(x: 100, y: 100))
        let result = try! XCTUnwrap(BevelTool.bevel(line1: a, line2: b, radius: 10))
        // Lines shortened to the tangent points; corner at (100, 0).
        assertPoint(result.line1.endPoint, 90, 0, "line1 trimmed to tangent")
        assertPoint(result.line2.startPoint, 100, 10, "line2 trimmed to tangent")
        XCTAssertEqual(result.arc.radius, 10, accuracy: 1e-4)
    }

    func testBevelReturnsNilWhenNotConnected() {
        let a = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        let b = LineShape(start: CGPoint(x: 200, y: 0), end: CGPoint(x: 200, y: 100))
        XCTAssertNil(BevelTool.bevel(line1: a, line2: b, radius: 10))
    }

    /// The fillet arc must trace the *minor* arc (bulging toward the corner), not
    /// the major arc looping the long way around. Regression for the "scooped the
    /// wrong way" bug: corner bottom-left, legs going up and right (Y-down space).
    func testBevelArcTracesMinorArcTowardCorner() {
        let corner = CGPoint(x: 0, y: 50)
        let vertical = LineShape(start: CGPoint(x: 0, y: 0), end: corner)        // leg up
        let horizontal = LineShape(start: corner, end: CGPoint(x: 50, y: 50))    // leg right
        let result = try! XCTUnwrap(BevelTool.bevel(line1: vertical, line2: horizontal, radius: 10))

        // Midpoint of the rendered arc should sit within one radius of the corner.
        let mid = result.arc.pointAtParameter(0.5)
        XCTAssertLessThan(mid.distance(to: corner), result.arc.radius,
                          "fillet arc must bulge toward the corner, not loop away")
    }

    func testFilletCornerReportsClockwiseForMinorArc() {
        // Same L-corner: start angle 180°, end angle 90° → CCW span 270°, so the
        // short way is clockwise.
        let fillet = try! XCTUnwrap(BevelTool.filletCorner(prev: CGPoint(x: 0, y: 0),
                                                           corner: CGPoint(x: 0, y: 50),
                                                           next: CGPoint(x: 50, y: 50),
                                                           radius: 10))
        XCTAssertTrue(fillet.clockwise)
    }

    // MARK: - arc → cubic approximation

    func testArcCubicMidpointLiesOnCircle() {
        // Quarter circle from (10,0) to (0,10) about center (10,10), r=10.
        let center = CGPoint(x: 10, y: 10)
        let from = CGPoint(x: 10, y: 0)
        let to = CGPoint(x: 0, y: 10)
        let (cOut, cIn) = BevelTool.arcToCubicControlPoints(from: from, to: to, center: center, radius: 10)
        // Evaluate the cubic at t = 0.5 and confirm it is ~on the circle.
        let mid = cubic(from, cOut, cIn, to, 0.5)
        XCTAssertEqual(center.distance(to: mid), 10, accuracy: 0.05,
                       "cubic midpoint should approximate the arc radius")
    }

    private func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                       y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    // MARK: - Bulk bevel (EditorViewModel)

    @MainActor
    private func makeEditor(_ shapes: [AnyShape]) -> EditorViewModel {
        let editor = EditorViewModel(document: .empty())
        editor.undoManager = UndoManager()
        editor.document.layers[0].shapes = shapes
        editor.selectedShapeIds = Set(shapes.map { $0.id })
        return editor
    }

    @MainActor
    func testBulkBevelSquareOfFourLines() {
        let a = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        let b = LineShape(start: CGPoint(x: 100, y: 0), end: CGPoint(x: 100, y: 100))
        let c = LineShape(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 0, y: 100))
        let d = LineShape(start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 0))
        let editor = makeEditor([.line(a), .line(b), .line(c), .line(d)])

        let count = editor.bevelSelectedCorners(radius: 10)
        XCTAssertEqual(count, 4, "all four square corners should be beveled")

        let shapes = editor.document.layers[0].shapes
        let arcs = shapes.filter { if case .arc = $0 { return true } else { return false } }
        XCTAssertEqual(arcs.count, 4, "one fillet arc per corner")

        // Line A (id preserved) is shortened by the radius at both ends.
        let beveledA = shapes.first { $0.id == a.id }
        if case .line(let la) = try! XCTUnwrap(beveledA) {
            assertPoint(la.startPoint, 10, 0, "A start trimmed")
            assertPoint(la.endPoint, 90, 0, "A end trimmed")
        } else {
            XCTFail("line A missing after bevel")
        }
    }

    @MainActor
    func testBulkBevelRectangleSetsCornerRadius() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 100, height: 80))
        let editor = makeEditor([.rectangle(rect)])

        let count = editor.bevelSelectedCorners(radius: 10)
        XCTAssertEqual(count, 4)

        guard case .rectangle(let out) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected a rectangle")
        }
        XCTAssertEqual(out.cornerRadius, 10, accuracy: 1e-6)
        XCTAssertEqual(out.id, rect.id, "rectangle stays the same shape (non-destructive)")
    }

    @MainActor
    func testBulkBevelRectangleClampsRadius() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 100, height: 80))
        let editor = makeEditor([.rectangle(rect)])

        editor.bevelSelectedCorners(radius: 1000)
        guard case .rectangle(let out) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected a rectangle")
        }
        XCTAssertEqual(out.cornerRadius, 40, accuracy: 1e-6, "clamped to min(w,h)/2")
    }

    @MainActor
    func testBulkBevelBezierPolylineCorner() {
        // Open L-shaped polyline bézier with straight (zero-handle) segments.
        let p0 = BezierPoint(point: CGPoint(x: 0, y: 0), controlIn: CGPoint(x: 0, y: 0), controlOut: CGPoint(x: 0, y: 0))
        let p1 = BezierPoint(point: CGPoint(x: 100, y: 0), controlIn: CGPoint(x: 100, y: 0), controlOut: CGPoint(x: 100, y: 0))
        let p2 = BezierPoint(point: CGPoint(x: 100, y: 100), controlIn: CGPoint(x: 100, y: 100), controlOut: CGPoint(x: 100, y: 100))
        let bezier = BezierShape(points: [p0, p1, p2], isClosed: false)
        let editor = makeEditor([.bezier(bezier)])

        let count = editor.bevelSelectedCorners(radius: 10)
        XCTAssertEqual(count, 1, "the single interior corner is filleted")

        guard case .bezier(let out) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected a bezier")
        }
        XCTAssertEqual(out.points.count, 4, "corner anchor replaced by two tangent anchors")
        assertPoint(out.points[1].point, 90, 0, "first tangent point")
        assertPoint(out.points[2].point, 100, 10, "second tangent point")
    }

    @MainActor
    func testBulkBevelSkipsVertexSharedByThreeLines() {
        // Three lines all meeting at the origin — ambiguous, must be skipped.
        let a = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        let b = LineShape(start: .zero, end: CGPoint(x: 0, y: 100))
        let c = LineShape(start: .zero, end: CGPoint(x: 70, y: 70))
        let editor = makeEditor([.line(a), .line(b), .line(c)])

        let count = editor.bevelSelectedCorners(radius: 10)
        XCTAssertEqual(count, 0, "a 3-way junction is not a bevelable corner")
        XCTAssertEqual(editor.document.layers[0].shapes.count, 3, "nothing added or removed")
    }

    @MainActor
    func testBevelableCornerCountMatchesSquare() {
        let a = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        let b = LineShape(start: CGPoint(x: 100, y: 0), end: CGPoint(x: 100, y: 100))
        let c = LineShape(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 0, y: 100))
        let d = LineShape(start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 0))
        let editor = makeEditor([.line(a), .line(b), .line(c), .line(d)])
        XCTAssertEqual(editor.bevelableCornerCount(radius: 10), 4)
    }

    @MainActor
    func testBulkBevelIsUndoable() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 100, height: 80))
        let editor = makeEditor([.rectangle(rect)])
        editor.bevelSelectedCorners(radius: 10)
        XCTAssertTrue(editor.undoManager?.canUndo ?? false)
        editor.undoManager?.undo()
        guard case .rectangle(let out) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected a rectangle")
        }
        XCTAssertEqual(out.cornerRadius, 0, accuracy: 1e-6, "undo restores the sharp corners")
    }

    // MARK: - Click bevel (single corner)

    @MainActor
    func testClickBevelRectangleExplodesAndRoundsClickedCorner() {
        // Corners: TL(0,0) TR(50,0) BR(50,50) BL(0,50).
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 50, height: 50))
        let editor = makeEditor([.rectangle(rect)])

        editor.bevelClickedCorner(shapeId: rect.id, near: CGPoint(x: 2, y: 48), radius: 10) // near BL

        let shapes = editor.document.layers[0].shapes
        XCTAssertNil(shapes.first { $0.id == rect.id }, "rectangle replaced by its edges")
        XCTAssertEqual(shapes.filter { if case .line = $0 { return true } else { return false } }.count, 4)
        let arcs = shapes.compactMap { shape -> ArcShape? in if case .arc(let a) = shape { return a } else { return nil } }
        XCTAssertEqual(arcs.count, 1, "only the clicked corner is filleted")
        // The fillet belongs to the bottom-left corner, not the opposite one.
        XCTAssertLessThan(arcs[0].center.x, 25)
        XCTAssertGreaterThan(arcs[0].center.y, 25)
    }

    @MainActor
    func testClickBevelRectangleTwoCornersIndependently() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 50, height: 50))
        let editor = makeEditor([.rectangle(rect)])

        editor.bevelClickedCorner(shapeId: rect.id, near: CGPoint(x: 2, y: 48), radius: 8)  // BL

        // After the explode, click the bottom-right corner via an edge touching it.
        let br = CGPoint(x: 50, y: 50)
        guard let edge = editor.document.layers[0].shapes.first(where: { shape in
            if case .line(let l) = shape { return l.startPoint.distance(to: br) < 0.6 || l.endPoint.distance(to: br) < 0.6 }
            return false
        }) else { return XCTFail("no edge at bottom-right") }
        editor.bevelClickedCorner(shapeId: edge.id, near: br, radius: 8)

        let shapes = editor.document.layers[0].shapes
        XCTAssertEqual(shapes.filter { if case .arc = $0 { return true } else { return false } }.count, 2,
                       "both bottom corners rounded, top corners untouched")
        XCTAssertEqual(shapes.filter { if case .line = $0 { return true } else { return false } }.count, 4)
    }

    @MainActor
    func testClickBevelAdjacentCornersWithHalfSideRadius() {
        // 20mm square, radius 10 (= half the side). Beveling one corner shortens the
        // shared edge to exactly the radius; the adjacent corner must still bevel
        // (the two fillets meet exactly). Regression: adjacent corner was skipped.
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 20, height: 20))
        let editor = makeEditor([.rectangle(rect)])

        editor.bevelClickedCorner(shapeId: rect.id, near: CGPoint(x: 1, y: 1), radius: 10)   // TL

        let tr = CGPoint(x: 20, y: 0)
        guard let edge = editor.document.layers[0].shapes.first(where: { shape in
            if case .line(let l) = shape { return l.startPoint.distance(to: tr) < 0.6 || l.endPoint.distance(to: tr) < 0.6 }
            return false
        }) else { return XCTFail("no edge at top-right") }
        editor.bevelClickedCorner(shapeId: edge.id, near: tr, radius: 10)   // adjacent TR

        let arcs = editor.document.layers[0].shapes.filter { if case .arc = $0 { return true } else { return false } }
        XCTAssertEqual(arcs.count, 2, "adjacent corner must bevel even when fillets meet exactly")
    }

    @MainActor
    func testClickBevelLinePicksCornerNearestClick() {
        let a = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        let b = LineShape(start: CGPoint(x: 100, y: 0), end: CGPoint(x: 100, y: 100))
        let c = LineShape(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 0, y: 100))
        let d = LineShape(start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 0))
        let editor = makeEditor([.line(a), .line(b), .line(c), .line(d)])

        // Click line A near the (0,0) corner — must bevel A∩D there, not A∩B at (100,0).
        editor.bevelClickedCorner(shapeId: a.id, near: CGPoint(x: 5, y: 0), radius: 5)

        let arcs = editor.document.layers[0].shapes.compactMap { shape -> ArcShape? in
            if case .arc(let arc) = shape { return arc } else { return nil }
        }
        XCTAssertEqual(arcs.count, 1)
        XCTAssertLessThan(arcs[0].center.x, 25, "fillet at the clicked (0,0) corner")
        XCTAssertLessThan(arcs[0].center.y, 25)
    }
}
