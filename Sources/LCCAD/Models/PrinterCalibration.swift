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

    /// Create a calibration from measured values.
    /// The user prints a 100mm square and measures the result.
    /// scaleX = 100.0 / measuredX, scaleY = 100.0 / measuredY
    static func fromMeasurement(printerName: String, measuredX: Double, measuredY: Double) -> PrinterCalibration {
        PrinterCalibration(
            printerName: printerName,
            scaleX: 100.0 / measuredX,
            scaleY: 100.0 / measuredY
        )
    }
}

// MARK: - Persistence

@MainActor
final class PrinterCalibrationStore: ObservableObject {
    @Published var calibrations: [PrinterCalibration] = []

    static let shared = PrinterCalibrationStore()

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LCCAD", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("printer_calibrations.json")
    }

    init() {
        load()
    }

    func load() {
        let url = Self.storageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            calibrations = try decoder.decode([PrinterCalibration].self, from: data)
        } catch {
            print("Failed to load printer calibrations: \(error)")
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(calibrations)
            try data.write(to: Self.storageURL, options: .atomic)
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
