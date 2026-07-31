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

    // MARK: - label placement (JIS 流)

    func testLabelPlacementHorizontal() {
        // 横線: 文字は左→右、ラベルは線の上 (Y 下向き座標なので -Y 側)
        let d = dim(CGPoint(x: 0, y: 10), CGPoint(x: 100, y: 10), offset: 5, kind: .horizontal)
        XCTAssertEqual(d.labelDirection.x, 1, accuracy: 1e-9)
        XCTAssertEqual(d.labelDirection.y, 0, accuracy: 1e-9)
        XCTAssertEqual(d.labelUpNormal.x, 0, accuracy: 1e-9)
        XCTAssertEqual(d.labelUpNormal.y, -1, accuracy: 1e-9)
        XCTAssertEqual(d.labelRotation, 0, accuracy: 1e-9)
        let c = d.labelCenter()
        XCTAssertEqual(c.x, d.labelAnchor.x, accuracy: 1e-9)
        XCTAssertLessThan(c.y, d.labelAnchor.y)  // 線より上
    }

    func testLabelPlacementVertical() {
        // 縦線: 文字は下→上 (90° 回転)、ラベルは線の左 (-X 側)
        let d = dim(CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 80), offset: 5, kind: .vertical)
        XCTAssertEqual(d.labelDirection.x, 0, accuracy: 1e-9)
        XCTAssertEqual(d.labelDirection.y, -1, accuracy: 1e-9)
        XCTAssertEqual(d.labelUpNormal.x, -1, accuracy: 1e-9)
        XCTAssertEqual(d.labelUpNormal.y, 0, accuracy: 1e-9)
        XCTAssertEqual(d.labelRotation, -CGFloat.pi / 2, accuracy: 1e-9)
        let c = d.labelCenter()
        XCTAssertLessThan(c.x, d.labelAnchor.x)  // 線より左
        XCTAssertEqual(c.y, d.labelAnchor.y, accuracy: 1e-9)
    }

    func testLabelDirectionNeverUpsideDown() {
        // 右→左に引いた横寸法でも文字方向は左→右に正規化される
        let d = dim(CGPoint(x: 100, y: 10), CGPoint(x: 0, y: 10), offset: 5, kind: .horizontal)
        XCTAssertEqual(d.labelDirection.x, 1, accuracy: 1e-9)
        XCTAssertEqual(d.labelDirection.y, 0, accuracy: 1e-9)
    }

    func testLabelPlacementAligned45Degrees() {
        // 45° の aligned 寸法: 文字方向は線に沿い、法線はその左 90°
        let d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), offset: 2, kind: .aligned)
        let inv = 1 / CGFloat(2).squareRoot()
        XCTAssertEqual(d.labelDirection.x, inv, accuracy: 1e-9)
        XCTAssertEqual(d.labelDirection.y, inv, accuracy: 1e-9)
        XCTAssertEqual(d.labelRotation, CGFloat.pi / 4, accuracy: 1e-9)
        XCTAssertEqual(d.labelUpNormal.x, inv, accuracy: 1e-9)
        XCTAssertEqual(d.labelUpNormal.y, -inv, accuracy: 1e-9)
    }

    func testLabelCenterClearanceMagnitude() {
        // 中心は labelAnchor から 文字高/2 + labelGap だけ離れる
        let d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), offset: 5, kind: .horizontal)
        let c = d.labelCenter()
        let expected = DimensionLineShape.textHeight / 2 + DimensionLineShape.labelGap
        XCTAssertEqual(d.labelAnchor.y - c.y, expected, accuracy: 1e-9)
    }

    // MARK: - label hit test

    func testHitTestOnLabelHorizontal() {
        // ラベルは線から離れているが、数値クリックでも選択できる
        let d = dim(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), offset: 10, kind: .horizontal)
        let c = d.labelCenter()
        XCTAssertTrue(d.hitTest(point: c, tolerance: 1))
        // ラベルからも線・矢印からも離れた点はヒットしない
        XCTAssertFalse(d.hitTest(point: CGPoint(x: c.x, y: c.y - 10), tolerance: 1))
    }

    func testHitTestOnLabelVertical() {
        // 縦寸法: 線の左に回転して置かれたラベルもヒット対象
        let d = dim(CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 80), offset: 5, kind: .vertical)
        let c = d.labelCenter()
        XCTAssertTrue(d.hitTest(point: c, tolerance: 1))
        // 回転後の文字進行方向 (Y 方向) にラベル半幅+tolerance を超えて離れるとヒットしない
        XCTAssertFalse(d.hitTest(point: CGPoint(x: c.x, y: c.y + 8), tolerance: 1))
    }
}
