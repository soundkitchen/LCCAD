import Foundation
import CoreGraphics

struct StitchHole: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var position: CGPoint   // world coordinates (mm)
    var angle: CGFloat      // radians — hole orientation (path tangent + iron angle)

    init(id: UUID = UUID(), position: CGPoint, angle: CGFloat = 0) {
        self.id = id
        self.position = position
        self.angle = angle
    }
}
