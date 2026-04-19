import Foundation

struct Layer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var isVisible: Bool
    var isLocked: Bool
    var shapes: [AnyShape]
    var stitchLines: [StitchLine]

    init(id: UUID = UUID(), name: String, isVisible: Bool = true,
         isLocked: Bool = false, shapes: [AnyShape] = [], stitchLines: [StitchLine] = []) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.shapes = shapes
        self.stitchLines = stitchLines
    }

    // Custom Decodable for backward compatibility with files lacking stitchLines
    enum CodingKeys: String, CodingKey {
        case id, name, isVisible, isLocked, shapes, stitchLines
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        shapes = try container.decode([AnyShape].self, forKey: .shapes)
        stitchLines = try container.decodeIfPresent([StitchLine].self, forKey: .stitchLines) ?? []
    }
}
