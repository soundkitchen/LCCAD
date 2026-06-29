import XCTest
@testable import LCCAD

final class AutoStitchTests: XCTestCase {

    func testFixedPitchOnLine() {
        let walker = LinePathWalker(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 100, y: 0)
        )
        let iron = PrickingIron(name: "Test", holeType: .diamond, pitch: 4.0)
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .fixedPitch)

        // 100mm line, 4mm pitch: holes at 0, 4, 8, ..., 100 = 26 holes
        XCTAssertEqual(holes.count, 26)

        // First hole at start
        XCTAssertEqual(holes[0].position.x, 0, accuracy: 0.001)
        XCTAssertEqual(holes[0].position.y, 0, accuracy: 0.001)

        // Second hole at pitch distance
        XCTAssertEqual(holes[1].position.x, 4, accuracy: 0.001)

        // Last hole at or near end
        XCTAssertEqual(holes.last!.position.x, 100, accuracy: 0.001)

        // All tangents should be 0 (horizontal line)
        for hole in holes {
            XCTAssertEqual(hole.angle, 0, accuracy: 0.001)
        }
    }

    func testVariablePitchOnLine() {
        let walker = LinePathWalker(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 10, y: 0)
        )
        let iron = PrickingIron(name: "Test", holeType: .round, pitch: 3.0)
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .variablePitch)

        // 10mm / 3mm = 3.33 → round to 3 segments → 4 holes
        // Adjusted pitch = 10/3 ≈ 3.333mm
        XCTAssertEqual(holes.count, 4)

        // First hole at start, last at end
        XCTAssertEqual(holes.first!.position.x, 0, accuracy: 0.001)
        XCTAssertEqual(holes.last!.position.x, 10, accuracy: 0.001)
    }

    func testEmptyPathProducesNoHoles() {
        let walker = LinePathWalker(
            start: CGPoint(x: 5, y: 5),
            end: CGPoint(x: 5, y: 5)
        )
        let iron = PrickingIron(name: "Test", holeType: .diamond, pitch: 4.0)
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron)
        XCTAssertTrue(holes.isEmpty)
    }

    func testLinePathWalkerLength() {
        let walker = LinePathWalker(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 3, y: 4)
        )
        XCTAssertEqual(walker.pathLength, 5.0, accuracy: 0.001)
    }

    func testLinePathWalkerMidpoint() {
        let walker = LinePathWalker(
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 10, y: 0)
        )
        let mid = walker.pointAtDistance(5)
        XCTAssertEqual(mid.x, 5.0, accuracy: 0.001)
        XCTAssertEqual(mid.y, 0.0, accuracy: 0.001)
    }

    func testArcPathWalkerLength() {
        // Semicircle: radius 10, sweep = pi → length = 10*pi ≈ 31.416
        let arc = ArcShape(center: CGPoint(x: 0, y: 0), radius: 10, startAngle: 0, endAngle: .pi, clockwise: false)
        let walker = ArcPathWalker(arc: arc)
        XCTAssertEqual(walker.pathLength, 10 * .pi, accuracy: 0.01)
    }

    func testBezierStraightLineLength() {
        // A straight-line bezier should have the same length as a line
        let walker = BezierSegmentPathWalker(
            p0: CGPoint(x: 0, y: 0),
            p1: CGPoint(x: 10, y: 0),
            p2: CGPoint(x: 20, y: 0),
            p3: CGPoint(x: 30, y: 0)
        )
        XCTAssertEqual(walker.pathLength, 30, accuracy: 0.5)
    }

    // MARK: - Ellipse / Circle

    func testCircleIsStitchable() {
        let circle = EllipseShape(center: .zero, radiusX: 10, radiusY: 10)
        guard let walker = PathWalkerFactory.walker(for: .ellipse(circle)) else {
            return XCTFail("circle should be stitchable")
        }
        XCTAssertTrue(walker.isClosed)
        XCTAssertEqual(walker.pathLength, 2 * .pi * 10, accuracy: 0.05)
    }

    func testEllipseWalkerArcLength() {
        let ellipse = EllipseShape(center: .zero, radiusX: 10, radiusY: 5)
        let walker = EllipsePathWalker(ellipse: ellipse)
        // Ramanujan approximation of the ellipse circumference ≈ 48.442
        XCTAssertEqual(walker.pathLength, 48.442, accuracy: 0.1)
    }

    func testVariablePitchCircleHasNoSeamDuplicate() {
        let circle = EllipseShape(center: .zero, radiusX: 10, radiusY: 10)
        let walker = PathWalkerFactory.walker(for: .ellipse(circle))!
        let iron = PrickingIron(name: "T", holeType: .round, pitch: 4)
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .variablePitch)
        // round(2π·10 / 4) = round(15.7) = 16 holes, evenly spread, no seam duplicate.
        XCTAssertEqual(holes.count, 16)
        XCTAssertGreaterThan(holes.first!.position.distance(to: holes.last!.position), 1.0)
    }

    func testFixedPitchRectangleAnchorsEveryCorner() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        XCTAssertTrue(walker.isClosed)
        XCTAssertEqual(walker.cornerDistances.count, 4, "a rectangle has four corners")
        let iron = PrickingIron(name: "T", holeType: .diamond, pitch: 4)
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .fixedPitch)
        // Each 10mm side is evened to round(10/4)=3 holes (~3.33mm apart) → 12 total.
        XCTAssertEqual(holes.count, 12)
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)] {
            XCTAssertTrue(hasHole(holes, near: corner), "no hole at corner \(corner)")
        }
    }

    /// The reported bug: when a span length isn't a whole multiple of the pitch, the holes
    /// must not bunch up next to a corner — spacing stays even on any shape, in either mode.
    func testNoClusteringNearCorners() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        let iron = PrickingIron(name: "T", holeType: .diamond, pitch: 3)  // 10 / 3 leaves a remainder
        for mode in [StitchMode.fixedPitch, .variablePitch] {
            let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: mode)
            for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)] {
                XCTAssertTrue(hasHole(holes, near: corner), "\(mode): no hole at corner \(corner)")
            }
            let gap = minConsecutiveGap(holes, closed: true)
            XCTAssertGreaterThan(gap, iron.pitch * 0.5, "\(mode): holes clustered (min gap \(gap)mm)")
        }
    }

    // MARK: - Welding (StitchPathBuilder)

    func testWeldTwoConnectedLinesIntoOnePath() {
        let l1 = AnyShape.line(LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0)))
        let l2 = AnyShape.line(LineShape(start: CGPoint(x: 10, y: 0), end: CGPoint(x: 10, y: 10)))
        let paths = StitchPathBuilder.build(from: [l1, l2])
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].sourceShapeIds.count, 2)
        XCTAssertEqual(paths[0].walker.pathLength, 20, accuracy: 0.001)
        XCTAssertFalse(paths[0].walker.isClosed)
    }

    func testWeldFourLinesIntoClosedLoop() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        let shapes = (0..<4).map { i in
            AnyShape.line(LineShape(start: pts[i], end: pts[(i + 1) % 4]))
        }
        let paths = StitchPathBuilder.build(from: shapes)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].sourceShapeIds.count, 4)
        XCTAssertTrue(paths[0].walker.isClosed)
        XCTAssertEqual(paths[0].walker.pathLength, 40, accuracy: 0.001)
        XCTAssertEqual(paths[0].walker.cornerDistances.count, 4, "welded square has four corners")

        // pitch 5 over 10mm sides → 2 holes per side (corner + midpoint) = 8, corners anchored.
        let iron = PrickingIron(name: "T", holeType: .diamond, pitch: 5)
        let holes = AutoStitchEngine.generateHoles(along: paths[0].walker, iron: iron, mode: .variablePitch)
        XCTAssertEqual(holes.count, 8)
        for corner in pts {
            XCTAssertTrue(hasHole(holes, near: corner), "no hole at corner \(corner)")
        }
    }

    /// A welded outline with a smooth (tangent) joint and one sharp corner anchors the
    /// corner but not the smooth joint — mirrors a pocket (sharp top corner, rounded base).
    func testSmoothJointIsNotTreatedAsCorner() {
        // Horizontal line into a quarter-ish arc that leaves tangent to the line.
        let line = AnyShape.line(LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0)))
        // Arc centered at (10,5), starting at (10,0) heading tangent to the line (downward turn).
        let arc = AnyShape.arc(ArcShape(center: CGPoint(x: 10, y: 5), radius: 5,
                                        startAngle: -.pi / 2, endAngle: 0, clockwise: false))
        let paths = StitchPathBuilder.build(from: [line, arc])
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(paths[0].walker.cornerDistances.isEmpty, "a tangent line→arc joint is not a corner")
    }

    private func hasHole(_ holes: [StitchHole], near point: CGPoint, tol: CGFloat = 0.01) -> Bool {
        holes.contains { $0.position.distance(to: point) <= tol }
    }

    private func minConsecutiveGap(_ holes: [StitchHole], closed: Bool) -> CGFloat {
        guard holes.count > 1 else { return .greatestFiniteMagnitude }
        var minGap = CGFloat.greatestFiniteMagnitude
        for i in 1..<holes.count {
            minGap = min(minGap, holes[i - 1].position.distance(to: holes[i].position))
        }
        if closed {
            minGap = min(minGap, holes.last!.position.distance(to: holes.first!.position))
        }
        return minGap
    }

    func testReversedSegmentStillWelds() {
        // The second line is drawn in reverse orientation but shares the (10,0) joint.
        let l1 = AnyShape.line(LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0)))
        let l2 = AnyShape.line(LineShape(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 10, y: 0)))
        let paths = StitchPathBuilder.build(from: [l1, l2])
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].walker.pathLength, 20, accuracy: 0.001)
    }

    func testSeparateClosedShapesStayDistinct() {
        let inner = AnyShape.ellipse(EllipseShape(center: .zero, radiusX: 5, radiusY: 5))
        let outer = AnyShape.ellipse(EllipseShape(center: .zero, radiusX: 10, radiusY: 10))
        let paths = StitchPathBuilder.build(from: [inner, outer])
        XCTAssertEqual(paths.count, 2)  // two parts → two stitch runs (駒合わせ setup)
    }

    func testWeldStopsAtLoopClosureIgnoringStray() {
        // Triangle L1→L2→L3 closes at (0,0); a stray L4 touching that seam must NOT be
        // absorbed (which would emit the closed triangle as an open path).
        let l1 = AnyShape.line(LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0)))
        let l2 = AnyShape.line(LineShape(start: CGPoint(x: 10, y: 0), end: CGPoint(x: 5, y: 10)))
        let l3 = AnyShape.line(LineShape(start: CGPoint(x: 5, y: 10), end: CGPoint(x: 0, y: 0)))
        let stray = AnyShape.line(LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: -5, y: -5)))
        let paths = StitchPathBuilder.build(from: [l1, l2, l3, stray])
        XCTAssertEqual(paths.count, 2, "closed triangle + stray = two paths")
        XCTAssertTrue(
            paths.contains { $0.walker.isClosed && $0.sourceShapeIds.count == 3 },
            "the triangle must stay a closed 3-segment loop"
        )
    }

    func testNestedCompositeSurfacesInnerCorners() {
        // An L-shaped inner composite (one 90° corner at distance 10) wrapped in an outer
        // composite must still surface that inner corner.
        let inner = CompositePathWalker(segments: [
            LinePathWalker(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0)),
            LinePathWalker(start: CGPoint(x: 10, y: 0), end: CGPoint(x: 10, y: 10)),
        ])
        XCTAssertEqual(inner.cornerDistances.count, 1)
        let outer = CompositePathWalker(segments: [
            inner,
            LinePathWalker(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 20, y: 10)),
        ])
        XCTAssertTrue(outer.cornerDistances.contains { abs($0 - 10) < 1e-6 }, "inner corner not surfaced")
    }

    func testReversedWalkerForwardsCorners() {
        let inner = CompositePathWalker(segments: [
            LinePathWalker(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0)),
            LinePathWalker(start: CGPoint(x: 10, y: 0), end: CGPoint(x: 10, y: 10)),
        ])
        // Inner corner at 10; reversed → pathLength(20) − 10 = 10.
        XCTAssertEqual(ReversedPathWalker(inner: inner).cornerDistances, [10])
    }
}
