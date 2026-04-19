import Foundation
import CoreGraphics

struct DotShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var position: CGPoint
    var radius: CGFloat
    var stroke: StrokeStyle
    var isLocked: Bool = false

    init(id: UUID = UUID(), position: CGPoint, radius: CGFloat = 1.5, stroke: StrokeStyle = .default) {
        self.id = id
        self.position = position
        self.radius = radius
        self.stroke = stroke
    }

    var boundingBox: CGRect {
        CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        point.distance(to: position) <= radius + tolerance
    }

    mutating func translate(by delta: CGPoint) {
        position = position + delta
    }
}
