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

    func testEchoOfCurrentColorIsNotApplied() {
        let black = CodableColor(r: 0, g: 0, b: 0)
        let echoed = CodableColor(r: 0.00000003, g: 0, b: 0)
        XCTAssertFalse(CodableColorPicker.shouldApply(echoed, to: [black]))
    }

    func testColorIsAppliedWhenSomeSelectedShapesDiffer() {
        // 黒と赤の線を選択し(先頭は黒)、黒を選んだら赤の線も黒になること (review #74)
        let black = CodableColor(r: 0, g: 0, b: 0)
        let red = CodableColor(r: 1, g: 0, b: 0)
        XCTAssertTrue(CodableColorPicker.shouldApply(black, to: [black, red]))
    }

    func testAlphaIsCompared() {
        let opaque = CodableColor(r: 0, g: 0, b: 0, a: 1)
        let translucent = CodableColor(r: 0, g: 0, b: 0, a: 0.5)
        XCTAssertFalse(opaque.isApproximatelyEqual(to: translucent))
    }
}

/// ピッカーで選んだ元の色を覚えておく仕組み (#72)
@MainActor
final class ColorPickerHistoryTests: XCTestCase {

    func testRestoringReturnsOriginalColorSpaceColor() throws {
        let history = ColorPickerHistory()
        // 汎用 RGB で明度 100% の色(カラーパネルが返しうる色)
        let original = NSColor(calibratedHue: 0.3, saturation: 0.9, brightness: 1, alpha: 1)
        let picked = Color(nsColor: original)
        let codable = try XCTUnwrap(CodableColor(picked))
        history.record(picked, as: codable)

        // 保存値(sRGB)から引くと、元の色空間の色が返り、明度も 100% のまま
        let restored = NSColor(try XCTUnwrap(history.originalColor(for: codable)))
        let inOriginalSpace = try XCTUnwrap(restored.usingColorSpace(original.colorSpace))
        XCTAssertEqual(inOriginalSpace.brightnessComponent, 1, accuracy: 1e-4)

        // 比較: 保存値をそのまま sRGB の色として戻すと明度が 100% を下回る(これを防ぐための仕組み)
        let srgb = try XCTUnwrap(NSColor(srgbRed: codable.r, green: codable.g, blue: codable.b, alpha: 1)
            .usingColorSpace(.sRGB))
        XCTAssertLessThan(srgb.brightnessComponent, 0.99)
    }

    func testUnknownColorReturnsNil() {
        let history = ColorPickerHistory()
        XCTAssertNil(history.originalColor(for: CodableColor(r: 0.1, g: 0.2, b: 0.3)))
    }

    func testOldestEntriesAreEvictedBeyondCapacity() {
        let history = ColorPickerHistory(capacity: 2)
        let colors = [0.1, 0.2, 0.3].map { CodableColor(r: $0, g: 0, b: 0) }
        for c in colors {
            history.record(Color(red: c.r, green: c.g, blue: c.b), as: c)
        }
        XCTAssertNil(history.originalColor(for: colors[0]))
        XCTAssertNotNil(history.originalColor(for: colors[1]))
        XCTAssertNotNil(history.originalColor(for: colors[2]))
    }

    func testRecordingSameColorAgainKeepsLatest() throws {
        let history = ColorPickerHistory(capacity: 2)
        let a = CodableColor(r: 0.1, g: 0, b: 0)
        let b = CodableColor(r: 0.2, g: 0, b: 0)
        history.record(Color(red: a.r, green: 0, blue: 0), as: a)
        history.record(Color(red: b.r, green: 0, blue: 0), as: b)
        // a を記録し直すと最新扱いになり、次の記録で追い出されるのは b
        history.record(Color(red: a.r, green: 0, blue: 0), as: a)
        history.record(Color(red: 0.3, green: 0, blue: 0), as: CodableColor(r: 0.3, g: 0, b: 0))
        XCTAssertNotNil(history.originalColor(for: a))
        XCTAssertNil(history.originalColor(for: b))
    }
}
