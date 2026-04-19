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
}
