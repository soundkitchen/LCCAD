import XCTest
@testable import LCCAD

final class EllipseShapeTests: XCTestCase {

    func testBoundingBoxUnrotatedMatchesRadii() {
        let e = EllipseShape(center: CGPoint(x: 30, y: 40), radiusX: 20, radiusY: 10)
        let bb = e.boundingBox
        XCTAssertEqual(bb.minX, 10, accuracy: 1e-9)
        XCTAssertEqual(bb.minY, 30, accuracy: 1e-9)
        XCTAssertEqual(bb.width, 40, accuracy: 1e-9)
        XCTAssertEqual(bb.height, 20, accuracy: 1e-9)
        // unrotatedBounds always reflects the raw radii regardless of rotation.
        XCTAssertEqual(e.unrotatedBounds, bb)
    }

    func testBoundingBoxRotated90SwapsExtents() {
        // A long ellipse (100 x 10) rotated 90° must become 10 x 100 — the case
        // that previously clipped in the SVG viewBox.
        var e = EllipseShape(center: CGPoint(x: 0, y: 0), radiusX: 50, radiusY: 5)
        e.rotation = .pi / 2
        let bb = e.boundingBox
        XCTAssertEqual(bb.width, 10, accuracy: 1e-6)
        XCTAssertEqual(bb.height, 100, accuracy: 1e-6)
        XCTAssertEqual(bb.midX, 0, accuracy: 1e-6)
        XCTAssertEqual(bb.midY, 0, accuracy: 1e-6)
        // The unrotated drawing bounds are unchanged (used by the renderers).
        XCTAssertEqual(e.unrotatedBounds.width, 100, accuracy: 1e-9)
        XCTAssertEqual(e.unrotatedBounds.height, 10, accuracy: 1e-9)
    }

    func testBoundingBoxRotated45ClosedForm() {
        // rx=10, ry=6 at 45°: half-extent = √(100·0.5 + 36·0.5) = √68 in both axes.
        var e = EllipseShape(center: CGPoint(x: 0, y: 0), radiusX: 10, radiusY: 6)
        e.rotation = .pi / 4
        let half = (68.0 as CGFloat).squareRoot()
        let bb = e.boundingBox
        XCTAssertEqual(bb.width, half * 2, accuracy: 1e-6)
        XCTAssertEqual(bb.height, half * 2, accuracy: 1e-6)
    }
}
