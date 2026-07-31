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
}
