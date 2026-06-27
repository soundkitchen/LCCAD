import Foundation
import CoreGraphics
import os

private let logger = Logger(subsystem: "org.izukawa.LCCAD", category: "templates")

// MARK: - Template Model

/// A reusable part / pattern saved to the global template library.
///
/// v1 stores geometry only (`[AnyShape]`) — stitch lines are intentionally not
/// captured because they reference pricking irons that may not exist in the
/// document the template is later placed into. Auto Stitch can be re-applied
/// after placement.
///
/// Shapes are stored normalized so their combined bounding box is centered on the
/// origin. Placement then translates the clones to the (snapped) cursor point, so
/// the template drops centered under the cursor regardless of where it was authored.
struct Template: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    /// Either the flattened selection, or a single `.group` when saved as a group.
    var shapes: [AnyShape]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, shapes: [AnyShape]) {
        self.id = id
        self.name = name
        self.shapes = shapes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Combined bounding box of all shapes (world mm), or nil when empty.
    var boundingBox: CGRect? {
        guard let first = shapes.first else { return nil }
        var box = first.boundingBox
        for shape in shapes.dropFirst() {
            box = box.union(shape.boundingBox)
        }
        return box
    }
}

// MARK: - Persistence

/// Global, app-wide template library shared across all documents.
/// Mirrors `PrinterCalibrationStore`: a `shared` singleton backed by a JSON file
/// under `~/Library/Application Support/LCCAD/`.
@MainActor
final class TemplateLibraryStore: ObservableObject {
    @Published var templates: [Template] = []

    static let shared = TemplateLibraryStore()

    private static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LCCAD", isDirectory: true)
    }

    private static var storageURL: URL {
        storageDirectory.appendingPathComponent("templates.json")
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
            templates = try decoder.decode([Template].self, from: data)
        } catch {
            // File doesn't exist yet or decode failed — keep current templates.
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
            let data = try encoder.encode(templates)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save templates: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Add a new template (newest first).
    func add(_ template: Template) {
        templates.insert(template, at: 0)
        save()
    }

    func delete(id: UUID) {
        templates.removeAll { $0.id == id }
        save()
    }
}
