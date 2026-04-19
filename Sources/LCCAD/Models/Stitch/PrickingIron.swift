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
    var holeSize: CGFloat    // mm — diameter/width of hole mark
    var holeAngle: CGFloat   // radians — rotation offset for non-round holes

    init(id: UUID = UUID(), name: String, holeType: HoleType,
         pitch: CGFloat = 4.0, holeSize: CGFloat = 1.0, holeAngle: CGFloat = 0) {
        self.id = id
        self.name = name
        self.holeType = holeType
        self.pitch = pitch
        self.holeSize = holeSize
        self.holeAngle = holeAngle
    }

    static let defaultDiamond = PrickingIron(
        name: "Diamond 4mm", holeType: .diamond, pitch: 4.0, holeSize: 1.0
    )
    static let defaultRound = PrickingIron(
        name: "Round 3mm", holeType: .round, pitch: 3.0, holeSize: 0.8
    )
}
