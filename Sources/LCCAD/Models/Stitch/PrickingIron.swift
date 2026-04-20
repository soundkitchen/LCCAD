import Foundation
import CoreGraphics

enum HoleType: String, Codable, Equatable, CaseIterable, Sendable {
    case diamond   // 菱目打ち
    case french    // ヨーロッパ目打ち
    case round     // 丸目打ち
    case flat      // 平目打ち
}

struct PrickingIron: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var holeType: HoleType
    var pitch: CGFloat       // mm — spacing between holes
    var teeth: Int           // number of teeth (blades)
    var holeSize: CGFloat    // mm — diameter/width of hole mark
    var holeAngle: CGFloat   // radians — rotation offset for non-round holes

    init(id: UUID = UUID(), name: String, holeType: HoleType,
         pitch: CGFloat = 4.0, teeth: Int = 4, holeSize: CGFloat = 1.0, holeAngle: CGFloat = 0) {
        self.id = id
        self.name = name
        self.holeType = holeType
        self.pitch = pitch
        self.teeth = teeth
        self.holeSize = holeSize
        self.holeAngle = holeAngle
    }

    // Custom Decodable for backward compatibility (teeth may be missing in old files)
    enum CodingKeys: String, CodingKey {
        case id, name, holeType, pitch, teeth, holeSize, holeAngle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        holeType = try container.decode(HoleType.self, forKey: .holeType)
        pitch = try container.decode(CGFloat.self, forKey: .pitch)
        teeth = try container.decodeIfPresent(Int.self, forKey: .teeth) ?? 4
        holeSize = try container.decode(CGFloat.self, forKey: .holeSize)
        holeAngle = try container.decode(CGFloat.self, forKey: .holeAngle)
    }

    static let defaultDiamond = PrickingIron(
        name: "Diamond 4mm", holeType: .diamond, pitch: 4.0, teeth: 4, holeSize: 1.0
    )
    static let defaultRound = PrickingIron(
        name: "Round 3mm", holeType: .round, pitch: 3.0, teeth: 4, holeSize: 0.8
    )
}
