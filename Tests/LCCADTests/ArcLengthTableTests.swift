import XCTest
@testable import LCCAD

final class ArcLengthTableTests: XCTestCase {

    // MARK: - Straight line (arc length linear in parameter)

    func testStraightLineTotalLength() {
        let table = ArcLengthTable(sampleCount: 10) { t in
            CGPoint(x: t * 100, y: 0)
        }
        XCTAssertEqual(table.totalLength, 100, accuracy: 1e-9)
    }

    func testStraightLineParameterIsProportional() {
        let table = ArcLengthTable(sampleCount: 10) { t in
            CGPoint(x: t * 100, y: 0)
        }
        XCTAssertEqual(table.parameter(atDistance: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(table.parameter(atDistance: 25), 0.25, accuracy: 1e-9)
        XCTAssertEqual(table.parameter(atDistance: 50), 0.5, accuracy: 1e-9)
        XCTAssertEqual(table.parameter(atDistance: 100), 1, accuracy: 1e-9)
        // Interpolation between samples (samples fall on multiples of 10).
        XCTAssertEqual(table.parameter(atDistance: 33), 0.33, accuracy: 1e-9)
    }

    func testDistanceOutsideRangeIsClamped() {
        let table = ArcLengthTable(sampleCount: 10) { t in
            CGPoint(x: t * 100, y: 0)
        }
        XCTAssertEqual(table.parameter(atDistance: -5), 0, accuracy: 1e-9)
        XCTAssertEqual(table.parameter(atDistance: 500), 1, accuracy: 1e-9)
    }

    // MARK: - maxParameter (ellipse-style theta range)

    func testCircleWithMaxParameterReturnsTheta() {
        let radius: CGFloat = 10
        let table = ArcLengthTable(sampleCount: 360, maxParameter: 2 * .pi) { theta in
            CGPoint(x: radius * cos(theta), y: radius * sin(theta))
        }
        // Chord-approximated circumference converges to 2πr.
        XCTAssertEqual(table.totalLength, 2 * .pi * radius, accuracy: 0.01)
        // Circle arc length is linear in theta, so half the length is θ = π.
        XCTAssertEqual(table.parameter(atDistance: table.totalLength / 2), .pi, accuracy: 1e-6)
        XCTAssertEqual(table.parameter(atDistance: table.totalLength), 2 * .pi, accuracy: 1e-9)
    }

    // MARK: - Degenerate curve (all samples coincide)

    func testDegenerateCurveHasZeroLengthAndStartParameter() {
        let table = ArcLengthTable(sampleCount: 10) { _ in
            CGPoint(x: 5, y: 5)
        }
        XCTAssertEqual(table.totalLength, 0)
        XCTAssertEqual(table.parameter(atDistance: 0), 0)
        XCTAssertEqual(table.parameter(atDistance: 42), 0)
    }
}
