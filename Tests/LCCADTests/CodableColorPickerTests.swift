import XCTest
import AppKit
@testable import LCCAD

/// カラーピッカーと CodableColor の変換 (#72)
final class CodableColorPickerTests: XCTestCase {

    func testRoundTripThroughColorStaysWithinTolerance() throws {
        let original = CodableColor(r: 0.2, g: 0.5, b: 0.8, a: 1)
        let color = NSColor(srgbRed: original.r, green: original.g, blue: original.b, alpha: original.a)
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

    @MainActor
    func testWellIsNotUpdatedWhenShowingSameColorWithinTolerance() {
        // ドラッグ中の再描画で誤差を含む色を渡し直すと、パネルの指示点が飛ぶ
        let history = ColorPickerHistory()
        let shown = NSColor(calibratedHue: 0.3, saturation: 0.02, brightness: 1, alpha: 1)
        let codable = CodableColor(shown)!
        XCTAssertNil(CodableColorPicker.colorToShow(for: codable, showing: shown, history: history))
    }

    @MainActor
    func testWellIsUpdatedWithOriginalColorAfterUndo() throws {
        let history = ColorPickerHistory()
        let picked = NSColor(calibratedHue: 0.3, saturation: 0.9, brightness: 1, alpha: 1)
        let codable = try XCTUnwrap(CodableColor(picked))
        history.record(picked, as: codable)
        // 別の色を表示中に、Undo で picked の保存値へ戻った
        let newColor = CodableColorPicker.colorToShow(
            for: codable, showing: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), history: history)
        XCTAssertTrue(try XCTUnwrap(newColor) === picked)
    }

    @MainActor
    func testWellIsUpdatedWithSRGBColorWhenUnknown() throws {
        let codable = CodableColor(r: 0.2, g: 0.4, b: 0.6, a: 1)
        let newColor = try XCTUnwrap(CodableColorPicker.colorToShow(
            for: codable, showing: nil, history: ColorPickerHistory()))
        XCTAssertTrue(try XCTUnwrap(CodableColor(newColor)).isApproximatelyEqual(to: codable))
    }

    /// コードからウェルの色を変えても action が送られない(送り返しが起きない)ことが前提
    @MainActor
    func testSettingWellColorDoesNotSendAction() {
        final class Receiver: NSObject {
            var count = 0
            @objc func changed(_ sender: NSColorWell) { count += 1 }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let well = NSColorWell(style: .minimal)
        window.contentView?.addSubview(well)
        let receiver = Receiver()
        well.target = receiver
        well.action = #selector(Receiver.changed(_:))
        well.activate(true)
        defer {
            well.deactivate()
            NSColorPanel.shared.orderOut(nil)
        }
        well.color = NSColor(srgbRed: 0.3, green: 0.6, blue: 0.2, alpha: 1)
        XCTAssertEqual(receiver.count, 0)
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
        let codable = try XCTUnwrap(CodableColor(original))
        history.record(original, as: codable)

        // 保存値(sRGB)から引くと、元の色空間の色が返り、明度も 100% のまま
        let restored = try XCTUnwrap(history.originalColor(for: codable))
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
            history.record(NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1), as: c)
        }
        XCTAssertNil(history.originalColor(for: colors[0]))
        XCTAssertNotNil(history.originalColor(for: colors[1]))
        XCTAssertNotNil(history.originalColor(for: colors[2]))
    }

    func testRecordingSameColorAgainKeepsLatest() throws {
        let history = ColorPickerHistory(capacity: 2)
        let a = CodableColor(r: 0.1, g: 0, b: 0)
        let b = CodableColor(r: 0.2, g: 0, b: 0)
        history.record(NSColor(srgbRed: a.r, green: 0, blue: 0, alpha: 1), as: a)
        history.record(NSColor(srgbRed: b.r, green: 0, blue: 0, alpha: 1), as: b)
        // a を記録し直すと最新扱いになり、次の記録で追い出されるのは b
        history.record(NSColor(srgbRed: a.r, green: 0, blue: 0, alpha: 1), as: a)
        history.record(NSColor(srgbRed: 0.3, green: 0, blue: 0, alpha: 1), as: CodableColor(r: 0.3, g: 0, b: 0))
        XCTAssertNotNil(history.originalColor(for: a))
        XCTAssertNil(history.originalColor(for: b))
    }
}
