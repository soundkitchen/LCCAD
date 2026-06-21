import XCTest
import CoreGraphics
@testable import LCCAD

final class DimensionLineShapeTests: XCTestCase {

    private func dim(_ start: CGPoint, _ end: CGPoint, offset: CGFloat, kind: DimensionKind) -> DimensionLineShape {
        DimensionLineShape(start: start, end: end, offset: offset, kind: kind)
    }

    // MARK: - measuredValue per kind

    func testMeasuredValueAligned() {
        let d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4), offset: 0, kind: .aligned)
        XCTAssertEqual(d.measuredValue, 5, accuracy: 1e-9)  // 3-4-5
    }

    func testMeasuredValueHorizontal() {
        let d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4), offset: 0, kind: .horizontal)
        XCTAssertEqual(d.measuredValue, 3, accuracy: 1e-9)  // |dx|
    }

    func testMeasuredValueVertical() {
        let d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4), offset: 0, kind: .vertical)
        XCTAssertEqual(d.measuredValue, 4, accuracy: 1e-9)  // |dy|
    }

    // MARK: - offset(start:end:third:kind:) signs

    func testOffsetHorizontalFromThird() {
        // horizontal: offset = third.y - midY (midY = 0)
        let o = DimensionLineShape.offset(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0),
                                          third: CGPoint(x: 5, y: 7), kind: .horizontal)
        XCTAssertEqual(o, 7, accuracy: 1e-9)
    }

    func testOffsetVerticalFromThird() {
        // vertical: offset = third.x - midX (midX = 0)
        let o = DimensionLineShape.offset(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 10),
                                          third: CGPoint(x: -4, y: 5), kind: .vertical)
        XCTAssertEqual(o, -4, accuracy: 1e-9)
    }

    func testOffsetAlignedIsSignedPerpendicular() {
        // start→end along +x → left normal = (0, 1); offset = (third - start)·n = third.y
        let o = DimensionLineShape.offset(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0),
                                          third: CGPoint(x: 5, y: 6), kind: .aligned)
        XCTAssertEqual(o, 6, accuracy: 1e-9)
    }

    // MARK: - dimEndpoints

    func testDimEndpointsHorizontal() {
        let d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 2), offset: 5, kind: .horizontal)
        let (a, b) = d.dimEndpoints
        // midY = 1, dimY = 1 + 5 = 6
        XCTAssertEqual(a.x, 0, accuracy: 1e-9); XCTAssertEqual(a.y, 6, accuracy: 1e-9)
        XCTAssertEqual(b.x, 10, accuracy: 1e-9); XCTAssertEqual(b.y, 6, accuracy: 1e-9)
    }

    func testDimEndpointsVertical() {
        let d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 10), offset: 5, kind: .vertical)
        let (a, b) = d.dimEndpoints
        // midX = 1, dimX = 1 + 5 = 6
        XCTAssertEqual(a.x, 6, accuracy: 1e-9); XCTAssertEqual(a.y, 0, accuracy: 1e-9)
        XCTAssertEqual(b.x, 6, accuracy: 1e-9); XCTAssertEqual(b.y, 10, accuracy: 1e-9)
    }

    // MARK: - mirror sign table

    func testMirrorAlignedNegatesOffsetOnAnyAxis() {
        var d1 = dim(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), offset: 5, kind: .aligned)
        d1.mirror(axis: .vertical(x: 0))
        XCTAssertEqual(d1.offset, -5, accuracy: 1e-9)

        var d2 = dim(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), offset: 5, kind: .aligned)
        d2.mirror(axis: .horizontal(y: 0))
        XCTAssertEqual(d2.offset, -5, accuracy: 1e-9)
    }

    func testMirrorHorizontalAcrossHorizontalAxisNegates() {
        var d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), offset: 5, kind: .horizontal)
        d.mirror(axis: .horizontal(y: 0))  // flips Y → a Y-offset must negate
        XCTAssertEqual(d.offset, -5, accuracy: 1e-9)
    }

    func testMirrorHorizontalAcrossVerticalAxisKeepsOffset() {
        var d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), offset: 5, kind: .horizontal)
        d.mirror(axis: .vertical(x: 0))  // flips X only → Y-offset unchanged
        XCTAssertEqual(d.offset, 5, accuracy: 1e-9)
    }

    func testMirrorVerticalAcrossVerticalAxisNegates() {
        var d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10), offset: 5, kind: .vertical)
        d.mirror(axis: .vertical(x: 0))  // flips X → an X-offset must negate
        XCTAssertEqual(d.offset, -5, accuracy: 1e-9)
    }

    // MARK: - labels

    func testDisplayLabelOverrideWins() {
        var d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), offset: 5, kind: .horizontal)
        d.labelOverride = "≈10"
        XCTAssertEqual(d.displayLabel(unit: .millimeters), "≈10")
    }

    func testDisplayLabelAutoConvertsUnit() {
        let d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 25.4, y: 0), offset: 5, kind: .horizontal)
        XCTAssertEqual(d.displayLabel(unit: .millimeters), "25.4")
        XCTAssertEqual(d.displayLabel(unit: .inches), "1.0")
    }

    // MARK: - translate keeps offset relative

    func testTranslateMovesPointsKeepsOffset() {
        var d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), offset: 5, kind: .horizontal)
        d.translate(by: CGPoint(x: 3, y: 7))
        XCTAssertEqual(d.start.x, 3, accuracy: 1e-9); XCTAssertEqual(d.start.y, 7, accuracy: 1e-9)
        XCTAssertEqual(d.end.x, 13, accuracy: 1e-9); XCTAssertEqual(d.end.y, 7, accuracy: 1e-9)
        XCTAssertEqual(d.offset, 5, accuracy: 1e-9)
    }
}
