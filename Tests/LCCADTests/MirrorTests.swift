import XCTest
@testable import LCCAD

final class MirrorTests: XCTestCase {

    // MARK: - CGPoint.mirrored

    func testPointMirroredAcrossVertical() {
        let p = CGPoint(x: 10, y: 5)
        let m = p.mirrored(across: .vertical(x: 0))
        XCTAssertEqual(m.x, -10, accuracy: 1e-9)
        XCTAssertEqual(m.y, 5, accuracy: 1e-9)
    }

    func testPointMirroredAcrossHorizontal() {
        let p = CGPoint(x: 10, y: 5)
        let m = p.mirrored(across: .horizontal(y: 0))
        XCTAssertEqual(m.x, 10, accuracy: 1e-9)
        XCTAssertEqual(m.y, -5, accuracy: 1e-9)
    }

    func testPointMirrorIsInvolution() {
        let p = CGPoint(x: 7, y: -3)
        let twice = p.mirrored(across: .vertical(x: 4)).mirrored(across: .vertical(x: 4))
        XCTAssertEqual(twice.x, p.x, accuracy: 1e-9)
        XCTAssertEqual(twice.y, p.y, accuracy: 1e-9)
    }

    // MARK: - LineShape

    func testLineMirrorVertical() {
        var line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 5))
        line.mirror(axis: .vertical(x: 5))
        XCTAssertEqual(line.startPoint.x, 10, accuracy: 1e-9)
        XCTAssertEqual(line.startPoint.y, 0, accuracy: 1e-9)
        XCTAssertEqual(line.endPoint.x, 0, accuracy: 1e-9)
        XCTAssertEqual(line.endPoint.y, 5, accuracy: 1e-9)
    }

    // MARK: - RectangleShape

    func testRectangleMirrorVertical() {
        var rect = RectangleShape(origin: CGPoint(x: 2, y: 3), size: CGSize(width: 4, height: 2))
        rect.mirror(axis: .vertical(x: 0))
        XCTAssertEqual(rect.origin.x, -6, accuracy: 1e-9)
        XCTAssertEqual(rect.origin.y, 3, accuracy: 1e-9)
        XCTAssertEqual(rect.size.width, 4, accuracy: 1e-9)
        XCTAssertEqual(rect.size.height, 2, accuracy: 1e-9)
    }

    func testRectangleMirrorHorizontal() {
        var rect = RectangleShape(origin: CGPoint(x: 2, y: 3), size: CGSize(width: 4, height: 2))
        rect.mirror(axis: .horizontal(y: 10))
        XCTAssertEqual(rect.origin.x, 2, accuracy: 1e-9)
        XCTAssertEqual(rect.origin.y, 15, accuracy: 1e-9)
        XCTAssertEqual(rect.size.width, 4, accuracy: 1e-9)
        XCTAssertEqual(rect.size.height, 2, accuracy: 1e-9)
    }

    // MARK: - EllipseShape

    func testEllipseMirrorPreservesShape() {
        var e = EllipseShape(center: CGPoint(x: 5, y: 0), radiusX: 3, radiusY: 1)
        e.mirror(axis: .horizontal(y: 0))
        XCTAssertEqual(e.center.x, 5, accuracy: 1e-9)
        XCTAssertEqual(e.center.y, 0, accuracy: 1e-9)
        XCTAssertEqual(e.radiusX, 3, accuracy: 1e-9)
        XCTAssertEqual(e.radiusY, 1, accuracy: 1e-9)
    }

    // MARK: - DotShape

    func testDotMirrorVertical() {
        var d = DotShape(position: CGPoint(x: 2, y: 2))
        d.mirror(axis: .vertical(x: 0))
        XCTAssertEqual(d.position.x, -2, accuracy: 1e-9)
        XCTAssertEqual(d.position.y, 2, accuracy: 1e-9)
    }

    // MARK: - TextShape

    func testTextMirrorMovesPositionOnly() {
        var t = TextShape(position: CGPoint(x: 10, y: 5), content: "Front")
        t.mirror(axis: .vertical(x: 0))
        XCTAssertEqual(t.position.x, -10, accuracy: 1e-9)
        XCTAssertEqual(t.position.y, 5, accuracy: 1e-9)
        XCTAssertEqual(t.content, "Front")
    }

    // MARK: - ArcShape

    func testArcMirrorVerticalFlipsClockwise() {
        // CCW quarter arc from (1,0) to (0,1), center=(0,0)
        var arc = ArcShape(center: .zero, radius: 1, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        arc.mirror(axis: .vertical(x: 0))
        XCTAssertEqual(arc.center.x, 0, accuracy: 1e-9)
        XCTAssertEqual(arc.center.y, 0, accuracy: 1e-9)
        XCTAssertEqual(arc.startAngle, .pi, accuracy: 1e-9)
        XCTAssertEqual(arc.endAngle, .pi / 2, accuracy: 1e-9)
        XCTAssertTrue(arc.clockwise)
        // start point should be (-1, 0), end point (0, 1)
        XCTAssertEqual(arc.startPoint.x, -1, accuracy: 1e-9)
        XCTAssertEqual(arc.startPoint.y, 0, accuracy: 1e-9)
        XCTAssertEqual(arc.endPoint.x, 0, accuracy: 1e-9)
        XCTAssertEqual(arc.endPoint.y, 1, accuracy: 1e-9)
    }

    func testArcMirrorHorizontalFlipsClockwise() {
        var arc = ArcShape(center: .zero, radius: 1, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        arc.mirror(axis: .horizontal(y: 0))
        XCTAssertEqual(arc.startAngle, 0, accuracy: 1e-9)
        XCTAssertEqual(arc.endAngle, -.pi / 2, accuracy: 1e-9)
        XCTAssertTrue(arc.clockwise)
        XCTAssertEqual(arc.startPoint.x, 1, accuracy: 1e-9)
        XCTAssertEqual(arc.startPoint.y, 0, accuracy: 1e-9)
        XCTAssertEqual(arc.endPoint.x, 0, accuracy: 1e-9)
        XCTAssertEqual(arc.endPoint.y, -1, accuracy: 1e-9)
    }

    func testArcMirrorIsInvolution() {
        var arc = ArcShape(center: CGPoint(x: 3, y: 2), radius: 5,
                           startAngle: .pi / 6, endAngle: .pi / 3, clockwise: false)
        let originalStart = arc.startPoint
        let originalEnd = arc.endPoint
        arc.mirror(axis: .vertical(x: 1))
        arc.mirror(axis: .vertical(x: 1))
        XCTAssertEqual(arc.center.x, 3, accuracy: 1e-9)
        XCTAssertEqual(arc.center.y, 2, accuracy: 1e-9)
        XCTAssertEqual(arc.startPoint.x, originalStart.x, accuracy: 1e-9)
        XCTAssertEqual(arc.startPoint.y, originalStart.y, accuracy: 1e-9)
        XCTAssertEqual(arc.endPoint.x, originalEnd.x, accuracy: 1e-9)
        XCTAssertEqual(arc.endPoint.y, originalEnd.y, accuracy: 1e-9)
    }

    // MARK: - BezierShape

    func testBezierMirrorReflectsEachControlPointInPlace() {
        let p0 = BezierPoint(
            point: CGPoint(x: 0, y: 0),
            controlIn: CGPoint(x: -1, y: -1),
            controlOut: CGPoint(x: 2, y: 0)
        )
        let p1 = BezierPoint(
            point: CGPoint(x: 10, y: 0),
            controlIn: CGPoint(x: 8, y: 0),
            controlOut: CGPoint(x: 11, y: 1)
        )
        var bez = BezierShape(points: [p0, p1])
        bez.mirror(axis: .vertical(x: 5))

        // Anchor[0]: (0,0) → (10,0). controlIn (-1,-1) → (11,-1). controlOut (2,0) → (8,0).
        XCTAssertEqual(bez.points[0].point.x, 10, accuracy: 1e-9)
        XCTAssertEqual(bez.points[0].point.y, 0, accuracy: 1e-9)
        XCTAssertEqual(bez.points[0].controlIn.x, 11, accuracy: 1e-9)
        XCTAssertEqual(bez.points[0].controlIn.y, -1, accuracy: 1e-9)
        XCTAssertEqual(bez.points[0].controlOut.x, 8, accuracy: 1e-9)
        XCTAssertEqual(bez.points[0].controlOut.y, 0, accuracy: 1e-9)

        // Anchor[1]: (10,0) → (0,0). controlIn (8,0) → (2,0). controlOut (11,1) → (-1,1).
        XCTAssertEqual(bez.points[1].point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(bez.points[1].point.y, 0, accuracy: 1e-9)
        XCTAssertEqual(bez.points[1].controlIn.x, 2, accuracy: 1e-9)
        XCTAssertEqual(bez.points[1].controlIn.y, 0, accuracy: 1e-9)
        XCTAssertEqual(bez.points[1].controlOut.x, -1, accuracy: 1e-9)
        XCTAssertEqual(bez.points[1].controlOut.y, 1, accuracy: 1e-9)
    }

    func testBezierMirrorPreservesCurveShape() {
        // Sample the original cubic Bezier on the segment, mirror each sample,
        // mirror the curve, then sample the mirrored curve at the same t values.
        // The two sets of points must match within tolerance.
        let p0 = BezierPoint(
            point: CGPoint(x: 0, y: 0),
            controlIn: CGPoint(x: -1, y: -1),
            controlOut: CGPoint(x: 3, y: 4)
        )
        let p1 = BezierPoint(
            point: CGPoint(x: 10, y: 0),
            controlIn: CGPoint(x: 7, y: 4),
            controlOut: CGPoint(x: 11, y: -1)
        )
        let bez = BezierShape(points: [p0, p1])
        let axis = MirrorAxis.vertical(x: 5)

        var mirrored = bez
        mirrored.mirror(axis: axis)

        for i in 0...20 {
            let t = CGFloat(i) / 20
            let original = cubicSample(t, bez.points[0].point, bez.points[0].controlOut,
                                       bez.points[1].controlIn, bez.points[1].point)
            let expected = original.mirrored(across: axis)
            let actual = cubicSample(t, mirrored.points[0].point, mirrored.points[0].controlOut,
                                     mirrored.points[1].controlIn, mirrored.points[1].point)
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, "t=\(t)")
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, "t=\(t)")
        }
    }

    private func cubicSample(_ t: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPoint {
        let mt = 1 - t
        let b0 = mt * mt * mt
        let b1 = 3 * mt * mt * t
        let b2 = 3 * mt * t * t
        let b3 = t * t * t
        return CGPoint(
            x: b0 * p0.x + b1 * p1.x + b2 * p2.x + b3 * p3.x,
            y: b0 * p0.y + b1 * p1.y + b2 * p2.y + b3 * p3.y
        )
    }

    func testBezierMirrorIsInvolution() {
        let p0 = BezierPoint(point: CGPoint(x: 0, y: 0),
                             controlIn: CGPoint(x: -1, y: -1),
                             controlOut: CGPoint(x: 2, y: 0))
        let p1 = BezierPoint(point: CGPoint(x: 10, y: 7),
                             controlIn: CGPoint(x: 8, y: 7),
                             controlOut: CGPoint(x: 11, y: 8))
        var bez = BezierShape(points: [p0, p1], isClosed: true)
        bez.mirror(axis: .horizontal(y: 3))
        bez.mirror(axis: .horizontal(y: 3))

        XCTAssertEqual(bez.points[0].point, p0.point)
        XCTAssertEqual(bez.points[0].controlIn, p0.controlIn)
        XCTAssertEqual(bez.points[0].controlOut, p0.controlOut)
        XCTAssertEqual(bez.points[1].point, p1.point)
        XCTAssertEqual(bez.points[1].controlIn, p1.controlIn)
        XCTAssertEqual(bez.points[1].controlOut, p1.controlOut)
        XCTAssertTrue(bez.isClosed)
    }

    // MARK: - GroupShape

    func testGroupMirrorRecursivelyAffectsChildren() {
        let line = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))
        let dot = DotShape(position: CGPoint(x: 5, y: 5))
        var group = GroupShape(children: [.line(line), .dot(dot)])
        group.mirror(axis: .vertical(x: 0))

        if case .line(let l) = group.children[0] {
            XCTAssertEqual(l.startPoint.x, 0, accuracy: 1e-9)
            XCTAssertEqual(l.endPoint.x, -10, accuracy: 1e-9)
        } else {
            XCTFail("expected line at index 0")
        }
        if case .dot(let d) = group.children[1] {
            XCTAssertEqual(d.position.x, -5, accuracy: 1e-9)
            XCTAssertEqual(d.position.y, 5, accuracy: 1e-9)
        } else {
            XCTFail("expected dot at index 1")
        }
    }

    func testGroupMirrorNested() {
        let inner = GroupShape(children: [.dot(DotShape(position: CGPoint(x: 1, y: 1)))])
        var outer = GroupShape(children: [.group(inner)])
        outer.mirror(axis: .vertical(x: 0))

        guard case .group(let g) = outer.children[0],
              case .dot(let d) = g.children[0] else {
            return XCTFail("nested structure not preserved")
        }
        XCTAssertEqual(d.position.x, -1, accuracy: 1e-9)
        XCTAssertEqual(d.position.y, 1, accuracy: 1e-9)
    }

    // MARK: - AnyShape dispatch

    func testAnyShapeMirrorDispatchesCorrectly() {
        var any: AnyShape = .line(LineShape(start: .zero, end: CGPoint(x: 4, y: 0)))
        any.mirror(axis: .vertical(x: 0))
        if case .line(let l) = any {
            XCTAssertEqual(l.endPoint.x, -4, accuracy: 1e-9)
        } else {
            XCTFail("expected line case")
        }
    }
}
