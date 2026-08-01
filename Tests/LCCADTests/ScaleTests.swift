import XCTest
@testable import LCCAD

final class ScaleTests: XCTestCase {

    // MARK: - CGPoint.scaled

    func testPointScaledAroundAnchor() {
        let p = CGPoint(x: 10, y: 6).scaled(around: CGPoint(x: 4, y: 2), sx: 2, sy: 3)
        XCTAssertEqual(p.x, 16, accuracy: 1e-9)
        XCTAssertEqual(p.y, 14, accuracy: 1e-9)
    }

    func testPointScaledIdentity() {
        let p = CGPoint(x: 7, y: -3).scaled(around: CGPoint(x: 1, y: 1), sx: 1, sy: 1)
        XCTAssertEqual(p.x, 7, accuracy: 1e-9)
        XCTAssertEqual(p.y, -3, accuracy: 1e-9)
    }

    // MARK: - LineShape

    func testLineScaleNonUniform() {
        var line = LineShape(start: .zero, end: CGPoint(x: 10, y: 4))
        line.scale(sx: 2, sy: 0.5, around: .zero)
        XCTAssertEqual(line.startPoint.x, 0, accuracy: 1e-9)
        XCTAssertEqual(line.startPoint.y, 0, accuracy: 1e-9)
        XCTAssertEqual(line.endPoint.x, 20, accuracy: 1e-9)
        XCTAssertEqual(line.endPoint.y, 2, accuracy: 1e-9)
    }

    // MARK: - RectangleShape

    func testRectangleScaleNonUniformKeepsAnchor() {
        var rect = RectangleShape(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 30, height: 40))
        rect.scale(sx: 2, sy: 0.5, around: CGPoint(x: 10, y: 20))
        XCTAssertEqual(rect.origin.x, 10, accuracy: 1e-9)
        XCTAssertEqual(rect.origin.y, 20, accuracy: 1e-9)
        XCTAssertEqual(rect.size.width, 60, accuracy: 1e-9)
        XCTAssertEqual(rect.size.height, 20, accuracy: 1e-9)
    }

    func testRectangleScaleScalesCornerRadius() {
        var rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10), cornerRadius: 2)
        rect.scale(sx: 3, sy: 3, around: .zero)
        XCTAssertEqual(rect.cornerRadius, 6, accuracy: 1e-9)
    }

    func testRotatedRectangleUniformScaleScalesBoundingBox() {
        var rect = RectangleShape(origin: CGPoint(x: 10, y: 10), size: CGSize(width: 20, height: 10), rotation: .pi / 6)
        let before = rect.boundingBox
        let anchor = before.origin
        rect.scale(sx: 2, sy: 2, around: anchor)
        let after = rect.boundingBox
        XCTAssertEqual(after.origin.x, anchor.x, accuracy: 1e-9)
        XCTAssertEqual(after.origin.y, anchor.y, accuracy: 1e-9)
        XCTAssertEqual(after.width, before.width * 2, accuracy: 1e-9)
        XCTAssertEqual(after.height, before.height * 2, accuracy: 1e-9)
        XCTAssertEqual(rect.rotation, .pi / 6, accuracy: 1e-9)
    }

    // MARK: - EllipseShape

    func testEllipseScaleNonUniform() {
        var ellipse = EllipseShape(center: CGPoint(x: 10, y: 10), radiusX: 4, radiusY: 6)
        ellipse.scale(sx: 2, sy: 0.5, around: .zero)
        XCTAssertEqual(ellipse.center.x, 20, accuracy: 1e-9)
        XCTAssertEqual(ellipse.center.y, 5, accuracy: 1e-9)
        XCTAssertEqual(ellipse.radiusX, 8, accuracy: 1e-9)
        XCTAssertEqual(ellipse.radiusY, 3, accuracy: 1e-9)
    }

    // MARK: - ArcShape (uniform only)

    func testArcUniformScaleScalesEndpoints() {
        var arc = ArcShape(center: CGPoint(x: 10, y: 4), radius: 5, startAngle: 0, endAngle: .pi / 2)
        let sp = arc.startPoint
        let ep = arc.endPoint
        arc.scale(sx: 2, sy: 2, around: .zero)
        XCTAssertEqual(arc.radius, 10, accuracy: 1e-9)
        XCTAssertEqual(arc.startPoint.x, sp.x * 2, accuracy: 1e-9)
        XCTAssertEqual(arc.startPoint.y, sp.y * 2, accuracy: 1e-9)
        XCTAssertEqual(arc.endPoint.x, ep.x * 2, accuracy: 1e-9)
        XCTAssertEqual(arc.endPoint.y, ep.y * 2, accuracy: 1e-9)
    }

    // MARK: - DotShape

    func testDotScaleMovesPositionKeepsRadius() {
        var dot = DotShape(position: CGPoint(x: 10, y: 10), radius: 1.5)
        dot.scale(sx: 2, sy: 2, around: .zero)
        XCTAssertEqual(dot.position.x, 20, accuracy: 1e-9)
        XCTAssertEqual(dot.position.y, 20, accuracy: 1e-9)
        XCTAssertEqual(dot.radius, 1.5, accuracy: 1e-9, "punch-mark radius must not scale")
    }

    // MARK: - DimensionLineShape

    func testDimensionHorizontalScaleScalesOffsetByY() {
        var dim = DimensionLineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0), offset: 5, kind: .horizontal)
        dim.scale(sx: 3, sy: 2, around: .zero)
        XCTAssertEqual(dim.start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(dim.end.x, 30, accuracy: 1e-9)
        XCTAssertEqual(dim.offset, 10, accuracy: 1e-9)
    }

    func testDimensionVerticalScaleScalesOffsetByX() {
        var dim = DimensionLineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 10), offset: 5, kind: .vertical)
        dim.scale(sx: 3, sy: 2, around: .zero)
        XCTAssertEqual(dim.end.y, 20, accuracy: 1e-9)
        XCTAssertEqual(dim.offset, 15, accuracy: 1e-9)
    }

    func testDimensionAlignedUniformScaleScalesOffset() {
        var dim = DimensionLineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10), offset: 5, kind: .aligned)
        dim.scale(sx: 2, sy: 2, around: .zero)
        XCTAssertEqual(dim.offset, 10, accuracy: 1e-9)
    }

    func testDimensionAlignedNonUniformScaleKeepsDimLineParallel() {
        // The dimension line must land exactly where the affine map sends it:
        // its perpendicular distance from the scaled baseline equals the
        // projection of the scaled offset vector onto the new left-normal.
        var dim = DimensionLineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10), offset: 5, kind: .aligned)
        let (a0, _) = dim.dimEndpoints
        let sx: CGFloat = 2, sy: CGFloat = 0.5
        // Affine image of one point of the old dim line:
        let mapped = CGPoint(x: a0.x * sx, y: a0.y * sy)
        dim.scale(sx: sx, sy: sy, around: .zero)
        let (a1, b1) = dim.dimEndpoints
        // The new dim line through a1-b1: check `mapped` lies on it (same
        // perpendicular distance from the new baseline).
        let dx = b1.x - a1.x, dy = b1.y - a1.y
        let len = (dx * dx + dy * dy).squareRoot()
        let cross = ((mapped.x - a1.x) * dy - (mapped.y - a1.y) * dx) / len
        XCTAssertEqual(cross, 0, accuracy: 1e-9, "affine-mapped point must lie on the new dimension line")
    }

    // MARK: - GroupShape

    func testGroupScaleRecursesIntoChildren() {
        let line = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))
        let dot = DotShape(position: CGPoint(x: 5, y: 5), radius: 1)
        var group = GroupShape(children: [.line(line), .dot(dot)])
        group.scale(sx: 2, sy: 2, around: .zero)
        guard case .line(let scaledLine) = group.children[0],
              case .dot(let scaledDot) = group.children[1] else {
            return XCTFail("children types must be preserved")
        }
        XCTAssertEqual(scaledLine.endPoint.x, 20, accuracy: 1e-9)
        XCTAssertEqual(scaledDot.position.x, 10, accuracy: 1e-9)
        XCTAssertEqual(scaledDot.position.y, 10, accuracy: 1e-9)
    }
}
