import XCTest
import CoreGraphics
@testable import LCCAD

/// Tests for the true cubic-cubic intersection primitive and the shape→cubic
/// conversions it relies on (Issue #15 parts 2 & 3).
final class BezierIntersectionTests: XCTestCase {

    private func assertPoint(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat,
                             accuracy: CGFloat, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: accuracy, "x \(message)", file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: accuracy, "y \(message)", file: file, line: line)
    }

    /// A symmetric bump cubic peaking at (50, 67.5) crossed by a horizontal line
    /// at y = 40. Closed-form crossings are t ≈ 0.18086 / 0.81914 at
    /// x ≈ 8.63 / 91.37 — values that fall strictly between polyline samples, so
    /// they exercise the subdivision rather than a lucky sample hit.
    func testCubicCubicTwoCrossings() {
        let bump = CubicSegment(p0: CGPoint(x: 0, y: 0), c1: CGPoint(x: 0, y: 90),
                                c2: CGPoint(x: 100, y: 90), p3: CGPoint(x: 100, y: 0))
        let level = CubicSegment(p0: CGPoint(x: -10, y: 40), c1: CGPoint(x: 30, y: 40),
                                 c2: CGPoint(x: 70, y: 40), p3: CGPoint(x: 110, y: 40))

        let hits = Intersection.cubicCubicIntersections(bump, level)
        XCTAssertEqual(hits.count, 2, "a symmetric bump crosses a level line exactly twice")

        let sorted = hits.sorted { $0.point.x < $1.point.x }
        assertPoint(sorted[0].point, 8.63, 40, accuracy: 0.1)
        assertPoint(sorted[1].point, 91.37, 40, accuracy: 0.1)
        XCTAssertEqual(sorted[0].ta, 0.18086, accuracy: 0.005)
        XCTAssertEqual(sorted[1].ta, 0.81914, accuracy: 0.005)
    }

    /// Two straight diagonals (expressed as cubics) cross once at (50, 50).
    func testCubicCubicSingleCrossing() {
        let up = CubicSegment(p0: .zero, c1: CGPoint(x: 33, y: 33),
                              c2: CGPoint(x: 67, y: 67), p3: CGPoint(x: 100, y: 100))
        let down = CubicSegment(p0: CGPoint(x: 0, y: 100), c1: CGPoint(x: 33, y: 67),
                                c2: CGPoint(x: 67, y: 33), p3: CGPoint(x: 100, y: 0))

        let hits = Intersection.cubicCubicIntersections(up, down)
        XCTAssertEqual(hits.count, 1)
        assertPoint(hits[0].point, 50, 50, accuracy: 0.05)
        XCTAssertEqual(hits[0].ta, 0.5, accuracy: 0.005)
    }

    /// Disjoint bounding boxes → no work, no false positives.
    func testCubicCubicNoCrossing() {
        let a = CubicSegment(p0: .zero, c1: CGPoint(x: 10, y: 0),
                             c2: CGPoint(x: 20, y: 0), p3: CGPoint(x: 30, y: 0))
        let b = CubicSegment(p0: CGPoint(x: 0, y: 100), c1: CGPoint(x: 10, y: 100),
                             c2: CGPoint(x: 20, y: 100), p3: CGPoint(x: 30, y: 100))
        XCTAssertTrue(Intersection.cubicCubicIntersections(a, b).isEmpty)
    }

    /// The cubic approximation of a quarter circle stays within ~1e-3·r of the
    /// true circle, validating `arcCubics` as an intersection proxy. The peak
    /// deviation sits near t ≈ 0.21 / 0.79 — the midpoint t=0.5 is an exact
    /// zero-error point — so sweep the whole span instead of trusting one sample
    /// (a single t=0.5 check would pass even with a degraded tangent handle).
    func testArcCubicsApproximatesCircle() {
        let r: CGFloat = 50
        let segs = Intersection.arcCubics(center: .zero, rx: r, ry: r,
                                          startAngle: 0, signedSpan: .pi / 2)
        XCTAssertEqual(segs.count, 1, "a 90° span needs exactly one cubic")
        for i in 0...20 {
            let t = CGFloat(i) / 20
            let p = segs[0].point(at: t)
            XCTAssertEqual(p.distance(to: .zero), r, accuracy: r * 1e-3, "off-circle at t=\(t)")
        }
    }

    /// A full ellipse becomes 4 cubics that are C0-continuous (each segment's end
    /// meets the next segment's start) and close back onto the start point.
    func testEllipseCubicsCloseTheLoop() {
        let segs = Intersection.arcCubics(center: .zero, rx: 40, ry: 20,
                                          startAngle: 0, signedSpan: 2 * .pi)
        XCTAssertEqual(segs.count, 4)
        assertPoint(segs.first!.p0, 40, 0, accuracy: 1e-6)   // angle 0
        // No gaps / reordering between adjacent segments.
        for i in 0..<(segs.count - 1) {
            XCTAssertEqual(segs[i].p3.x, segs[i + 1].p0.x, accuracy: 1e-9, "junction \(i) x")
            XCTAssertEqual(segs[i].p3.y, segs[i + 1].p0.y, accuracy: 1e-9, "junction \(i) y")
        }
        assertPoint(segs.last!.p3, 40, 0, accuracy: 1e-4)    // wraps back to start
    }
}
