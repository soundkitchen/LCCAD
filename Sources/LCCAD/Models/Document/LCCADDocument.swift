import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Document Data (Codable payload)

struct DocumentData: Codable, Equatable, Sendable {
    var version: String = "1.0"
    var settings: ProjectSettings
    var prickingIrons: [PrickingIron]
    var layers: [Layer]

    init(settings: ProjectSettings = ProjectSettings(),
         prickingIrons: [PrickingIron]? = nil,
         layers: [Layer]? = nil) {
        self.settings = settings
        self.prickingIrons = prickingIrons ?? [PrickingIron.defaultDiamond]
        self.layers = layers ?? [Layer(name: "Layer 1")]
    }

    static func empty() -> DocumentData {
        DocumentData()
    }

    // Custom Decodable for backward compatibility with files lacking prickingIrons
    enum CodingKeys: String, CodingKey {
        case version, settings, prickingIrons, layers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        settings = try container.decode(ProjectSettings.self, forKey: .settings)
        prickingIrons = try container.decodeIfPresent([PrickingIron].self, forKey: .prickingIrons)
            ?? [PrickingIron.defaultDiamond]
        layers = try container.decode([Layer].self, forKey: .layers)
    }
}

// MARK: - UTType for .lccad files

extension UTType {
    static let lccad = UTType(exportedAs: "org.izukawa.LCCAD.document", conformingTo: .json)
}

// MARK: - Observable Document Container

@MainActor
final class LCCADFileDocument: ObservableObject {
    @Published var data: DocumentData
    @Published var fileURL: URL?

    /// Snapshot of `data` as of the last successful save / open / new.
    /// `isModified` compares the live `data` against this baseline.
    @Published private(set) var lastSavedData: DocumentData

    init(data: DocumentData = .empty(), fileURL: URL? = nil) {
        self.data = data
        self.fileURL = fileURL
        self.lastSavedData = data
    }

    /// `true` when there are unsaved edits relative to the last saved baseline.
    var isModified: Bool { data != lastSavedData }

    /// Record the current `data` as the saved baseline (clears the dirty state).
    func markSaved() {
        lastSavedData = data
    }
}
