import XCTest
import CoreGraphics
@testable import LCCAD

/// Tests for `TrimTool.trim`. The tool's helpers are private, so every case is
/// driven through the public `trim(shape:against:clickPoint:)` entry point and
/// asserts on the returned replacement shapes.
final class TrimToolTests: XCTestCase {

    // MARK: - Helpers

    private func line(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat) -> LineShape {
        LineShape(start: CGPoint(x: ax, y: ay), end: CGPoint(x: bx, y: by))
    }

    /// Pull the (start, end) endpoints out of a `.line` replacement.
    private func endpoints(_ shape: AnyShape) -> (CGPoint, CGPoint)? {
        guard case .line(let l) = shape else { return nil }
        return (l.startPoint, l.endPoint)
    }

    private func assertPoint(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat,
                             accuracy: CGFloat = 1e-6, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: accuracy, "x \(message)", file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: accuracy, "y \(message)", file: file, line: line)
    }

    // MARK: - Line trim

    /// A horizontal line crossed once near the middle: clicking the left part
    /// removes [0, t] and keeps the single right remnant.
    func testLineSingleIntersectionKeepsFarSide() {
        let target = AnyShape.line(line(0, 0, 100, 0))
        let crosser = AnyShape.line(line(50, -10, 50, 10))

        let result = TrimTool.trim(shape: target, against: [crosser], clickPoint: CGPoint(x: 25, y: 0))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.replacements.count, 1)

        let (s, e) = try! XCTUnwrap(endpoints(result!.replacements[0]))
        assertPoint(s, 50, 0)
        assertPoint(e, 100, 0)
    }

    /// Two crossers split the line into three; clicking the middle removes it
    /// and leaves the two outer remnants.
    func testLineTwoIntersectionsRemovesMiddle() {
        let target = AnyShape.line(line(0, 0, 100, 0))
        let crosserA = AnyShape.line(line(30, -10, 30, 10))
        let crosserB = AnyShape.line(line(70, -10, 70, 10))

        let result = TrimTool.trim(shape: target, against: [crosserA, crosserB], clickPoint: CGPoint(x: 50, y: 0))
        let replacements = try! XCTUnwrap(result?.replacements)
        XCTAssertEqual(replacements.count, 2)

        let segments = replacements.compactMap(endpoints).sorted { $0.0.x < $1.0.x }
        XCTAssertEqual(segments.count, 2)
        assertPoint(segments[0].0, 0, 0)
        assertPoint(segments[0].1, 30, 0)
        assertPoint(segments[1].0, 70, 0)
        assertPoint(segments[1].1, 100, 0)
    }

    /// No intersection → nothing to trim.
    func testLineNoIntersectionReturnsNil() {
        let target = AnyShape.line(line(0, 0, 100, 0))
        let nonCrosser = AnyShape.line(line(0, 50, 100, 50))
        XCTAssertNil(TrimTool.trim(shape: target, against: [nonCrosser], clickPoint: CGPoint(x: 50, y: 0)))
    }

    // MARK: - Arc trim (Arc-Line)

    /// Upper-half arc (radius 50) crossed by the y-axis at (0, 50). Clicking the
    /// right lobe removes [0, t] and keeps the arc from the crossing to the end.
    func testArcLineKeepsFarLobe() {
        let arc = ArcShape(center: .zero, radius: 50, startAngle: 0, endAngle: .pi)
        let target = AnyShape.arc(arc)
        let crosser = AnyShape.line(line(0, -5, 0, 60)) // hits only (0, 50) within the arc

        // Click near angle π/4 → on the right lobe (between start and the crossing).
        let a: CGFloat = .pi / 4
        let clickPoint = CGPoint(x: 50 * cos(a), y: 50 * sin(a))
        let result = TrimTool.trim(shape: target, against: [crosser], clickPoint: clickPoint)
        let replacements = try! XCTUnwrap(result?.replacements)
        XCTAssertEqual(replacements.count, 1)

        guard case .arc(let kept) = replacements[0] else { return XCTFail("expected arc") }
        // Kept arc runs from the crossing (π/2) to the original end (π).
        assertPoint(kept.pointAtParameter(0), 0, 50, accuracy: 1e-4)
        assertPoint(kept.pointAtParameter(1), -50, 0, accuracy: 1e-4)
    }

    // MARK: - Arc trim (Arc-Arc, analytical)

    /// Two overlapping circles' arcs intersect at (40, ±30). Trimming the first
    /// arc and clicking the middle lobe (angle 0) removes the central span and
    /// keeps the two outer remnants — exercising the analytical arc-arc path.
    func testArcArcRemovesMiddle() {
        let arc1 = ArcShape(center: .zero, radius: 50, startAngle: -1.0, endAngle: 1.0)
        let arc2 = ArcShape(center: CGPoint(x: 80, y: 0), radius: 50, startAngle: 2.0, endAngle: 4.3)

        let result = TrimTool.trim(shape: .arc(arc1), against: [.arc(arc2)],
                                   clickPoint: CGPoint(x: 50, y: 0))
        let replacements = try! XCTUnwrap(result?.replacements)
        XCTAssertEqual(replacements.count, 2)
        for r in replacements {
            guard case .arc = r else { return XCTFail("expected arc remnants") }
        }
    }

    // MARK: - Rectangle trim (explode clicked edge)

    /// Clicking a rectangle's top edge, crossed once, keeps the 3 other edges
    /// intact plus the remaining part of the clicked edge.
    func testRectangleTrimsClickedEdgeOnly() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 100, height: 100))
        let crosser = AnyShape.line(line(50, -10, 50, 10)) // crosses top edge at (50, 0)

        let result = TrimTool.trim(shape: .rectangle(rect), against: [crosser],
                                   clickPoint: CGPoint(x: 25, y: 0))
        let replacements = try! XCTUnwrap(result?.replacements)
        // 3 untouched edges + 1 remnant of the clicked top edge.
        XCTAssertEqual(replacements.count, 4)

        // The remnant of the clicked edge runs from the crossing to the corner.
        let topRemnant = replacements.compactMap(endpoints).first { seg in
            abs(seg.0.y) < 1e-6 && abs(seg.1.y) < 1e-6 &&
            (abs(seg.0.x - 50) < 1e-6 || abs(seg.1.x - 50) < 1e-6)
        }
        XCTAssertNotNil(topRemnant, "expected a trimmed top-edge remnant starting at x=50")
    }

    // MARK: - Ellipse trim (circle case, closed curve)

    /// A circle (equal radii) cut by a horizontal diameter at (±50, 0). Clicking
    /// the upper half removes it and keeps the lower semicircle as one arc.
    func testCircleTrimKeepsOppositeHalf() {
        let circle = EllipseShape(center: .zero, radiusX: 50, radiusY: 50)
        let diameter = AnyShape.line(line(-60, 0, 60, 0))

        let result = TrimTool.trim(shape: .ellipse(circle), against: [diameter],
                                   clickPoint: CGPoint(x: 0, y: 50))
        let replacements = try! XCTUnwrap(result?.replacements)
        XCTAssertEqual(replacements.count, 1)

        guard case .arc(let kept) = replacements[0] else { return XCTFail("expected arc") }
        // Lower semicircle: midpoint sits at the bottom (0, -50).
        assertPoint(kept.pointAtParameter(0.5), 0, -50, accuracy: 1e-4)
    }

    // MARK: - Bezier trim (Bezier-Line)

    /// A (geometrically straight) bezier crossed once by a vertical line.
    /// Clicking the left part keeps the right remnant as a bezier.
    func testBezierLineKeepsFarSide() {
        let pts = [
            BezierPoint(point: CGPoint(x: 0, y: 0),
                        controlIn: CGPoint(x: 0, y: 0),
                        controlOut: CGPoint(x: 33, y: 0)),
            BezierPoint(point: CGPoint(x: 100, y: 0),
                        controlIn: CGPoint(x: 67, y: 0),
                        controlOut: CGPoint(x: 100, y: 0)),
        ]
        let target = AnyShape.bezier(BezierShape(points: pts, isClosed: false))
        let crosser = AnyShape.line(line(50, -10, 50, 10))

        let result = TrimTool.trim(shape: target, against: [crosser], clickPoint: CGPoint(x: 25, y: 0))
        let replacements = try! XCTUnwrap(result?.replacements)
        XCTAssertEqual(replacements.count, 1)

        guard case .bezier(let kept) = replacements[0] else { return XCTFail("expected bezier") }
        assertPoint(kept.points.first!.point, 50, 0, accuracy: 1.0)
        assertPoint(kept.points.last!.point, 100, 0, accuracy: 1.0)
    }

    // MARK: - Curve × curve (true cubic-cubic intersection)

    /// Bezier-Bezier: two diagonals crossing at (50, 50). Clicking the lower-left
    /// part keeps the far half — routed through the analytical cubic path.
    func testBezierBezierKeepsFarSide() {
        let up = BezierShape(points: [
            BezierPoint(point: CGPoint(x: 0, y: 0), controlIn: .zero, controlOut: CGPoint(x: 33, y: 33)),
            BezierPoint(point: CGPoint(x: 100, y: 100), controlIn: CGPoint(x: 67, y: 67), controlOut: CGPoint(x: 100, y: 100)),
        ])
        let down = BezierShape(points: [
            BezierPoint(point: CGPoint(x: 0, y: 100), controlIn: CGPoint(x: 0, y: 100), controlOut: CGPoint(x: 33, y: 67)),
            BezierPoint(point: CGPoint(x: 100, y: 0), controlIn: CGPoint(x: 67, y: 33), controlOut: CGPoint(x: 100, y: 0)),
        ])

        let result = TrimTool.trim(shape: .bezier(up), against: [.bezier(down)],
                                   clickPoint: CGPoint(x: 25, y: 25))
        let replacements = try! XCTUnwrap(result?.replacements)
        XCTAssertEqual(replacements.count, 1)

        guard case .bezier(let kept) = replacements[0] else { return XCTFail("expected bezier") }
        assertPoint(kept.points.first!.point, 50, 50, accuracy: 0.5)
        assertPoint(kept.points.last!.point, 100, 100, accuracy: 0.5)
    }

    /// Arc-Bezier: an upper semicircle crossed by a straight bezier along the
    /// y-axis at (0, 50). Clicking the right lobe keeps the far arc.
    func testArcBezierKeepsFarLobe() {
        let arc = ArcShape(center: .zero, radius: 50, startAngle: 0, endAngle: .pi)
        let crosser = BezierShape(points: [
            BezierPoint(point: CGPoint(x: 0, y: -10), controlIn: CGPoint(x: 0, y: -10), controlOut: CGPoint(x: 0, y: 13)),
            BezierPoint(point: CGPoint(x: 0, y: 60), controlIn: CGPoint(x: 0, y: 37), controlOut: CGPoint(x: 0, y: 60)),
        ])

        let a: CGFloat = .pi / 4
        let clickPoint = CGPoint(x: 50 * cos(a), y: 50 * sin(a))
        let result = TrimTool.trim(shape: .arc(arc), against: [.bezier(crosser)], clickPoint: clickPoint)
        let replacements = try! XCTUnwrap(result?.replacements)
        XCTAssertEqual(replacements.count, 1)

        guard case .arc(let kept) = replacements[0] else { return XCTFail("expected arc") }
        assertPoint(kept.pointAtParameter(0), 0, 50, accuracy: 0.05)
        assertPoint(kept.pointAtParameter(1), -50, 0, accuracy: 0.05)
    }

    /// Ellipse(circle)-Bezier: a circle (r=40) cut by a straight bezier on the
    /// y-axis at (0, ±40). Clicking the left half keeps the right semicircle.
    func testCircleBezierKeepsOppositeHalf() {
        let circle = EllipseShape(center: .zero, radiusX: 40, radiusY: 40)
        let crosser = BezierShape(points: [
            BezierPoint(point: CGPoint(x: 0, y: -50), controlIn: CGPoint(x: 0, y: -50), controlOut: CGPoint(x: 0, y: -17)),
            BezierPoint(point: CGPoint(x: 0, y: 50), controlIn: CGPoint(x: 0, y: 17), controlOut: CGPoint(x: 0, y: 50)),
        ])

        let result = TrimTool.trim(shape: .ellipse(circle), against: [.bezier(crosser)],
                                   clickPoint: CGPoint(x: -40, y: 0))
        let replacements = try! XCTUnwrap(result?.replacements)
        XCTAssertEqual(replacements.count, 1)

        guard case .arc(let kept) = replacements[0] else { return XCTFail("expected arc") }
        assertPoint(kept.pointAtParameter(0.5), 40, 0, accuracy: 0.1)
    }

    /// Non-circular ellipse (rx ≠ ry) cut by a vertical diameter at (0, ±20).
    /// Clicking the left half keeps the right half, which — being a true ellipse
    /// rather than a circle — is emitted as a bezier via `ellipseArcToBezier`
    /// (the path refactored onto `arcCubics`). This is the only coverage of that
    /// non-circular extraction branch.
    func testEllipseTrimNonCircularKeepsBezierHalf() {
        let ellipse = EllipseShape(center: .zero, radiusX: 40, radiusY: 20)
        let diameter = AnyShape.line(line(0, -30, 0, 30)) // crosses at (0, 20) and (0, -20)

        let result = TrimTool.trim(shape: .ellipse(ellipse), against: [diameter],
                                   clickPoint: CGPoint(x: -40, y: 0))
        let replacements = try! XCTUnwrap(result?.replacements)
        XCTAssertEqual(replacements.count, 1)

        guard case .bezier(let kept) = replacements[0] else { return XCTFail("expected bezier remnant") }
        // π/2 + π/2 span → 2 cubics → 3 anchors, threading the right-side apex.
        XCTAssertEqual(kept.points.count, 3)
        assertPoint(kept.points.first!.point, 0, -20, accuracy: 0.5)
        assertPoint(kept.points[1].point, 40, 0, accuracy: 0.5)
        assertPoint(kept.points.last!.point, 0, 20, accuracy: 0.5)
    }
}
