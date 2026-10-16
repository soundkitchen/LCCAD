import XCTest
import SwiftUI
@testable import LCCAD

/// カラーピッカーと CodableColor の変換 (#72)
final class CodableColorPickerTests: XCTestCase {

    func testRoundTripThroughColorStaysWithinTolerance() throws {
        let original = CodableColor(r: 0.2, g: 0.5, b: 0.8, a: 1)
        let color = Color(red: original.r, green: original.g, blue: original.b, opacity: original.a)
        let roundTripped = try XCTUnwrap(CodableColor(color))
        // 往復で Float 精度の誤差が出ても、同じ色として扱われること(送り返しを変更とみなさない)
        XCTAssertTrue(roundTripped.isApproximatelyEqual(to: original))
    }

    func testOneLevelOf8BitIsTreatedAsChange() {
        let base = CodableColor(r: 0.5, g: 0.5, b: 0.5, a: 1)
        let oneStep = CodableColor(r: 0.5 + 1.0 / 255.0, g: 0.5, b: 0.5, a: 1)
        XCTAssertFalse(base.isApproximatelyEqual(to: oneStep),
                       "A visible change (one 8-bit level) must not be swallowed as noise")
    }

    func testAlphaIsCompared() {
        let opaque = CodableColor(r: 0, g: 0, b: 0, a: 1)
        let translucent = CodableColor(r: 0, g: 0, b: 0, a: 0.5)
        XCTAssertFalse(opaque.isApproximatelyEqual(to: translucent))
    }
}
