import XCTest
import CoreGraphics
@testable import LCCAD

final class StrokeStyleTests: XCTestCase {

    private func decode(_ json: String) throws -> StrokeStyle {
        try JSONDecoder().decode(StrokeStyle.self, from: Data(json.utf8))
    }

    // MARK: - Fixed width normalization

    func testLegacyWidthNormalizesToFixedWidth() throws {
        // Old files carry user-set widths (default used to be 0.25)
        let stroke = try decode(
            #"{"color":{"r":0,"g":0,"b":0,"a":1},"width":0.25}"#)
        XCTAssertEqual(stroke.width, StrokeStyle.fixedWidth)
        XCTAssertEqual(stroke.lineStyle, .solid)
        XCTAssertNil(stroke.dashPattern)
    }

    func testNewStrokeUsesFixedWidth() {
        XCTAssertEqual(StrokeStyle.default.width, StrokeStyle.fixedWidth)
        XCTAssertEqual(StrokeStyle(color: .stitch, lineStyle: .dashed).width,
                       StrokeStyle.fixedWidth)
    }

    func testWidthKeyStaysInEncodedOutput() throws {
        // Kept for file-format compatibility
        let data = try JSONEncoder().encode(StrokeStyle.default)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"width\""))
    }

    // MARK: - dashPattern re-derivation on decode

    func testStaleDashPatternOnSolidStrokeIsCleared() throws {
        let stroke = try decode(
            #"{"color":{"r":0,"g":0,"b":0,"a":1},"width":0.25,"lineStyle":"solid","dashPattern":[3,2]}"#)
        XCTAssertNil(stroke.dashPattern,
                     "solid stroke must not keep a leftover dash pattern")
    }

    func testStoredDashPatternIsRederivedFromLineStyle() throws {
        let stroke = try decode(
            #"{"color":{"r":0,"g":0,"b":0,"a":1},"width":0.25,"lineStyle":"dashed","dashPattern":[3,2]}"#)
        XCTAssertEqual(stroke.dashPattern, LineStyle.dashed.dashPattern,
                       "stored coarse pattern must be replaced by the current definition")
    }
}
