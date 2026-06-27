import XCTest
import CoreGraphics
@testable import LCCAD

/// Tests for `OffsetTool`. Each overload is internal `static`, so it is called
/// directly. Offsets use the left-side perpendicular convention: positive
/// distance moves a left-to-right horizontal line in +y.
final class OffsetToolTests: XCTestCase {

    private func assertPoint(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat,
                             accuracy: CGFloat = 1e-6, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.x, x, accuracy: accuracy, "x \(message)", file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: accuracy, "y \(message)", file: file, line: line)
    }

    // MARK: - Line

    func testOffsetLinePositiveMovesLeftPerpendicular() {
        let l = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        let out = OffsetTool.offsetLine(l, distance: 10)
        assertPoint(out.startPoint, 0, 10)
        assertPoint(out.endPoint, 100, 10)
    }

    func testOffsetLineNegativeMovesOppositeSide() {
        let l = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        let out = OffsetTool.offsetLine(l, distance: -10)
        assertPoint(out.startPoint, 0, -10)
        assertPoint(out.endPoint, 100, -10)
    }

    func testOffsetLineDegenerateReturnsSame() {
        let l = LineShape(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5))
        let out = OffsetTool.offsetLine(l, distance: 10)
        assertPoint(out.startPoint, 5, 5)
        assertPoint(out.endPoint, 5, 5)
    }

    // MARK: - Rectangle

    func testOffsetRectangleInsetsAllSides() {
        let r = RectangleShape(origin: .zero, size: CGSize(width: 100, height: 80), cornerRadius: 5)
        let out = OffsetTool.offsetRectangle(r, distance: 10)
        assertPoint(out.origin, 10, 10)
        XCTAssertEqual(out.size.width, 80, accuracy: 1e-6)
        XCTAssertEqual(out.size.height, 60, accuracy: 1e-6)
        XCTAssertEqual(out.cornerRadius, 0, accuracy: 1e-6) // max(0, 5 - 10)
    }

    func testOffsetRectangleClampsToZeroWhenOverInset() {
        let r = RectangleShape(origin: .zero, size: CGSize(width: 100, height: 80))
        let out = OffsetTool.offsetRectangle(r, distance: 60) // 2*60 > both extents
        XCTAssertEqual(out.size.width, 0, accuracy: 1e-6)
        XCTAssertEqual(out.size.height, 0, accuracy: 1e-6)
    }

    // MARK: - Ellipse

    func testOffsetEllipseShrinksRadii() {
        let e = EllipseShape(center: CGPoint(x: 10, y: 20), radiusX: 50, radiusY: 30)
        let out = OffsetTool.offsetEllipse(e, distance: 10)
        assertPoint(out.center, 10, 20)
        XCTAssertEqual(out.radiusX, 40, accuracy: 1e-6)
        XCTAssertEqual(out.radiusY, 20, accuracy: 1e-6)
    }

    func testOffsetEllipseClampsRadiiToZero() {
        let e = EllipseShape(center: .zero, radiusX: 50, radiusY: 30)
        let out = OffsetTool.offsetEllipse(e, distance: 60)
        XCTAssertEqual(out.radiusX, 0, accuracy: 1e-6)
        XCTAssertEqual(out.radiusY, 0, accuracy: 1e-6)
    }

    // MARK: - Arc

    func testOffsetArcInwardReducesRadiusPreservesAngles() {
        let arc = ArcShape(center: CGPoint(x: 1, y: 2), radius: 50,
                           startAngle: 0.2, endAngle: 1.7, clockwise: false)
        let out = try! XCTUnwrap(OffsetTool.offsetArc(arc, distance: 10))
        XCTAssertEqual(out.radius, 40, accuracy: 1e-6)
        XCTAssertEqual(out.startAngle, 0.2, accuracy: 1e-6)
        XCTAssertEqual(out.endAngle, 1.7, accuracy: 1e-6)
        assertPoint(out.center, 1, 2)
    }

    func testOffsetArcOutwardIncreasesRadius() {
        let arc = ArcShape(center: .zero, radius: 50, startAngle: 0, endAngle: .pi)
        let out = try! XCTUnwrap(OffsetTool.offsetArc(arc, distance: -10))
        XCTAssertEqual(out.radius, 60, accuracy: 1e-6)
    }

    func testOffsetArcReturnsNilWhenRadiusNonPositive() {
        let arc = ArcShape(center: .zero, radius: 50, startAngle: 0, endAngle: .pi)
        XCTAssertNil(OffsetTool.offsetArc(arc, distance: 50))  // radius → 0
        XCTAssertNil(OffsetTool.offsetArc(arc, distance: 60))  // radius → negative
    }

    // MARK: - Bezier

    /// A geometrically straight bezier offset by 10 on the left side produces a
    /// parallel curve whose endpoints shift by exactly (0, +10).
    func testOffsetBezierStraightIsParallel() {
        let pts = [
            BezierPoint(point: CGPoint(x: 0, y: 0),
                        controlIn: CGPoint(x: 0, y: 0),
                        controlOut: CGPoint(x: 33, y: 0)),
            BezierPoint(point: CGPoint(x: 100, y: 0),
                        controlIn: CGPoint(x: 67, y: 0),
                        controlOut: CGPoint(x: 100, y: 0)),
        ]
        let out = OffsetTool.offsetBezier(BezierShape(points: pts, isClosed: false), distance: 10)
        XCTAssertGreaterThanOrEqual(out.points.count, 2)
        assertPoint(out.points.first!.point, 0, 10, accuracy: 1e-4)
        assertPoint(out.points.last!.point, 100, 10, accuracy: 1e-4)
    }

    /// Offsetting preserves the closed flag.
    func testOffsetBezierPreservesClosedFlag() {
        let pts = [
            BezierPoint(point: CGPoint(x: 0, y: 0),
                        controlIn: CGPoint(x: -10, y: 0),
                        controlOut: CGPoint(x: 10, y: 0)),
            BezierPoint(point: CGPoint(x: 50, y: 50),
                        controlIn: CGPoint(x: 50, y: 40),
                        controlOut: CGPoint(x: 50, y: 60)),
            BezierPoint(point: CGPoint(x: 0, y: 100),
                        controlIn: CGPoint(x: 10, y: 100),
                        controlOut: CGPoint(x: -10, y: 100)),
        ]
        let out = OffsetTool.offsetBezier(BezierShape(points: pts, isClosed: true), distance: 5)
        XCTAssertTrue(out.isClosed)
    }

    func testOffsetBezierDegenerateReturnsInput() {
        let pts = [
            BezierPoint(point: .zero, controlIn: .zero, controlOut: .zero),
        ]
        let out = OffsetTool.offsetBezier(BezierShape(points: pts, isClosed: false), distance: 10)
        XCTAssertEqual(out.points.count, 1)
    }
}
