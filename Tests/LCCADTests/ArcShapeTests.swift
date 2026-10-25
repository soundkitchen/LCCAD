import XCTest
@testable import LCCAD

final class ArcShapeTests: XCTestCase {

    private func rad(_ deg: CGFloat) -> CGFloat { deg * .pi / 180 }

    // MARK: - normalizeAngle 境界値(PR #54 レビュー指摘)

    func testNormalizeAngleWrapsOutOfRangeInput() {
        let arc = ArcShape(center: .zero, radius: 10, startAngle: 0, endAngle: rad(90))
        XCTAssertEqual(arc.normalizeAngle(rad(450)), rad(90), accuracy: 1e-9)
        XCTAssertEqual(arc.normalizeAngle(rad(-400)), rad(320), accuracy: 1e-9)
        XCTAssertEqual(arc.normalizeAngle(rad(-30)), rad(330), accuracy: 1e-9)
        XCTAssertEqual(arc.normalizeAngle(rad(720)), 0, accuracy: 1e-9)
    }

    func testAngleSpanStaysInRangeWithNormalizedCommit() {
        // S に 450° を入力しても正規化後 (90°) なら退化しない:
        // E=90° と一致するため span は 0 ではなく全周 360° になる
        var arc = ArcShape(center: .zero, radius: 10, startAngle: 0, endAngle: rad(90))
        arc.startAngle = arc.normalizeAngle(rad(450))
        XCTAssertEqual(arc.angleSpan, 2 * .pi, accuracy: 1e-9)
        XCTAssertFalse(arc.pointAtParameter(0.5).x.isNaN)

        // S に 720° → 0°。通常の 0〜90° の弧に戻る
        arc.startAngle = arc.normalizeAngle(rad(720))
        XCTAssertEqual(arc.angleSpan, rad(90), accuracy: 1e-9)

        // S に -400° → 320°。ccw で 320°→90° は 130°
        arc.startAngle = arc.normalizeAngle(rad(-400))
        XCTAssertEqual(arc.angleSpan, rad(130), accuracy: 1e-9)
        XCTAssertGreaterThan(arc.angleSpan, 0)
        XCTAssertLessThanOrEqual(arc.angleSpan, 2 * .pi)
    }

    // MARK: - setRadiusKeepingEndpoints(R を変えても始点・終点を固定)

    private func assertPoint(_ a: CGPoint, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, file: file, line: line)
    }

    func testSetRadiusKeepsEndpointsAndBulgeOfQuarterArc() throws {
        // (10,0) → (0,10) を (8,6) 経由で描いた 1/4 円弧(中心 (0,0)、R10)
        let original = try XCTUnwrap(EditorViewModel.arcFrom3Points(
            p1: CGPoint(x: 10, y: 0), p2: CGPoint(x: 0, y: 10), p3: CGPoint(x: 8, y: 6)))
        let s = original.startPoint, e = original.endPoint
        let bulge = original.pointAtParameter(0.5)

        var arc = original
        XCTAssertTrue(arc.setRadiusKeepingEndpoints(20))
        XCTAssertEqual(arc.radius, 20)
        assertPoint(arc.startPoint, s)
        assertPoint(arc.endPoint, e)
        XCTAssertEqual(arc.clockwise, original.clockwise)
        // R を大きくすると平らになるが、劣弧のまま同じ側(原点の反対側)に膨らむ
        XCTAssertLessThan(arc.angleSpan, rad(90))
        let flatter = arc.pointAtParameter(0.5)
        XCTAssertGreaterThan(flatter.x + flatter.y, 10)
        XCTAssertLessThan(flatter.x + flatter.y, bulge.x + bulge.y)

        // R を 10 に戻すと元の 1/4 円弧に戻る
        XCTAssertTrue(arc.setRadiusKeepingEndpoints(10))
        assertPoint(arc.center, .zero)
        XCTAssertEqual(arc.angleSpan, rad(90), accuracy: 1e-9)
        assertPoint(arc.startPoint, s)
        assertPoint(arc.endPoint, e)
    }

    func testSetRadiusKeepsMajorArcMajor() {
        // 0° → 90° を時計回り(画面上)に回る 270° の優弧
        var arc = ArcShape(center: .zero, radius: 10, startAngle: 0, endAngle: rad(90), clockwise: true)
        let s = arc.startPoint, e = arc.endPoint
        XCTAssertEqual(arc.angleSpan, rad(270), accuracy: 1e-9)

        XCTAssertTrue(arc.setRadiusKeepingEndpoints(20))
        assertPoint(arc.startPoint, s)
        assertPoint(arc.endPoint, e)
        XCTAssertGreaterThan(arc.angleSpan, .pi)
    }

    func testSetRadiusRejectsRadiusShorterThanHalfChord() {
        // 弦長 10√2 の 1/4 円弧。R は 5√2 未満にできない
        let original = ArcShape(center: .zero, radius: 10, startAngle: 0, endAngle: rad(90))
        var arc = original
        XCTAssertFalse(arc.setRadiusKeepingEndpoints(7))
        XCTAssertEqual(arc, original)

        // ちょうど弦長の半分なら半円になる
        XCTAssertTrue(arc.setRadiusKeepingEndpoints(5 * sqrt(2)))
        XCTAssertEqual(arc.angleSpan, .pi, accuracy: 1e-6)
        assertPoint(arc.startPoint, original.startPoint)
        assertPoint(arc.endPoint, original.endPoint)
    }

    func testSetRadiusOnSemicircleBecomesMinorArcOnSameSide() {
        // 中心が弦上にある半円 (10,0) → (-10,0)。膨らみは y 正側
        var arc = ArcShape(center: .zero, radius: 10, startAngle: 0, endAngle: .pi)
        XCTAssertGreaterThan(arc.pointAtParameter(0.5).y, 0)

        XCTAssertTrue(arc.setRadiusKeepingEndpoints(20))
        XCTAssertLessThan(arc.angleSpan, .pi)
        XCTAssertGreaterThan(arc.pointAtParameter(0.5).y, 0)
        assertPoint(arc.startPoint, CGPoint(x: 10, y: 0))
        assertPoint(arc.endPoint, CGPoint(x: -10, y: 0))
    }

    func testSetRadiusOnFullCircleScalesAroundCenter() {
        // 始点と終点が一致する全周は弦が定まらないので、中心固定で半径だけ変える
        var arc = ArcShape(center: CGPoint(x: 5, y: 5), radius: 10, startAngle: 0, endAngle: 0)
        XCTAssertTrue(arc.setRadiusKeepingEndpoints(20))
        XCTAssertEqual(arc.radius, 20)
        assertPoint(arc.center, CGPoint(x: 5, y: 5))
    }
}
