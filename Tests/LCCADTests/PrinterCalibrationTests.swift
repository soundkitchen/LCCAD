import XCTest
@testable import LCCAD

final class PrinterCalibrationTests: XCTestCase {

    // MARK: - fromMeasurement validation

    func testFromMeasurementAcceptsNormalValues() {
        let cal = PrinterCalibration.fromMeasurement(printerName: "Printer", measuredX: 148.5, measuredY: 151.0)
        XCTAssertNotNil(cal)
        XCTAssertEqual(cal?.scaleX ?? 0, 150.0 / 148.5, accuracy: 1e-9)
        XCTAssertEqual(cal?.scaleY ?? 0, 150.0 / 151.0, accuracy: 1e-9)
    }

    func testFromMeasurementRejectsZero() {
        XCTAssertNil(PrinterCalibration.fromMeasurement(printerName: "P", measuredX: 0, measuredY: 150))
        XCTAssertNil(PrinterCalibration.fromMeasurement(printerName: "P", measuredX: 150, measuredY: 0))
    }

    func testFromMeasurementRejectsNegative() {
        XCTAssertNil(PrinterCalibration.fromMeasurement(printerName: "P", measuredX: -150, measuredY: 150))
    }

    func testFromMeasurementRejectsNonFinite() {
        XCTAssertNil(PrinterCalibration.fromMeasurement(printerName: "P", measuredX: .infinity, measuredY: 150))
        XCTAssertNil(PrinterCalibration.fromMeasurement(printerName: "P", measuredX: .nan, measuredY: 150))
    }

    func testFromMeasurementRejectsOutOfRange() {
        // Just outside the accepted 100-200 range
        XCTAssertNil(PrinterCalibration.fromMeasurement(printerName: "P", measuredX: 99.0, measuredY: 150))
        XCTAssertNil(PrinterCalibration.fromMeasurement(printerName: "P", measuredX: 150, measuredY: 201.0))
    }

    func testFromMeasurementAcceptsRangeBoundaries() {
        XCTAssertNotNil(PrinterCalibration.fromMeasurement(printerName: "P", measuredX: 100, measuredY: 200))
        XCTAssertNotNil(PrinterCalibration.fromMeasurement(printerName: "P", measuredX: 200, measuredY: 100))
    }

    // MARK: - isValidMeasurement

    func testIsValidMeasurement() {
        XCTAssertTrue(PrinterCalibration.isValidMeasurement(150))
        XCTAssertTrue(PrinterCalibration.isValidMeasurement(100))
        XCTAssertTrue(PrinterCalibration.isValidMeasurement(200))
        XCTAssertFalse(PrinterCalibration.isValidMeasurement(99.99))
        XCTAssertFalse(PrinterCalibration.isValidMeasurement(200.01))
        XCTAssertFalse(PrinterCalibration.isValidMeasurement(0))
        XCTAssertFalse(PrinterCalibration.isValidMeasurement(-1))
        XCTAssertFalse(PrinterCalibration.isValidMeasurement(.infinity))
        XCTAssertFalse(PrinterCalibration.isValidMeasurement(.nan))
    }
}
