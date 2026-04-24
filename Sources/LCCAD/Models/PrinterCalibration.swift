import Foundation

// MARK: - Printer Calibration Model

struct PrinterCalibration: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var printerName: String
    var scaleX: Double  // correction factor (default: 1.0)
    var scaleY: Double  // correction factor (default: 1.0)
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), printerName: String, scaleX: Double = 1.0, scaleY: Double = 1.0) {
        self.id = id
        self.printerName = printerName
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Valid measurement range for the 150mm calibration square (mm).
    /// 100-200mm covers ±33% which is well beyond any realistic printer error;
    /// values outside this range are almost certainly a unit mistake or typo.
    static let validMeasurementRange: ClosedRange<Double> = 100.0...200.0

    /// Create a calibration from measured values. Returns nil if a measurement
    /// is non-finite, non-positive, or outside `validMeasurementRange`.
    /// The user prints a 150mm square and measures the result.
    /// scaleX = 150.0 / measuredX, scaleY = 150.0 / measuredY
    static func fromMeasurement(printerName: String, measuredX: Double, measuredY: Double) -> PrinterCalibration? {
        guard isValidMeasurement(measuredX), isValidMeasurement(measuredY) else { return nil }
        return PrinterCalibration(
            printerName: printerName,
            scaleX: 150.0 / measuredX,
            scaleY: 150.0 / measuredY
        )
    }

    static func isValidMeasurement(_ value: Double) -> Bool {
        value.isFinite && validMeasurementRange.contains(value)
    }
}

// MARK: - Persistence

@MainActor
final class PrinterCalibrationStore: ObservableObject {
    @Published var calibrations: [PrinterCalibration] = []

    static let shared = PrinterCalibrationStore()

    private static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LCCAD", isDirectory: true)
    }

    private static var storageURL: URL {
        storageDirectory.appendingPathComponent("printer_calibrations.json")
    }

    init() {
        load()
    }

    func load() {
        let url = Self.storageURL
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([PrinterCalibration].self, from: data)
            calibrations = loaded
        } catch {
            // File doesn't exist yet or decode failed — keep current calibrations
        }
    }

    func save() {
        let dir = Self.storageDirectory
        let url = Self.storageURL
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(calibrations)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save printer calibrations: \(error)")
        }
    }

    func calibration(forPrinter name: String) -> PrinterCalibration? {
        calibrations.first { $0.printerName == name }
    }

    func addOrUpdate(_ calibration: PrinterCalibration) {
        if let index = calibrations.firstIndex(where: { $0.id == calibration.id }) {
            var updated = calibration
            updated.updatedAt = Date()
            calibrations[index] = updated
        } else {
            calibrations.append(calibration)
        }
        save()
    }

    func delete(id: UUID) {
        calibrations.removeAll { $0.id == id }
        save()
    }
}
