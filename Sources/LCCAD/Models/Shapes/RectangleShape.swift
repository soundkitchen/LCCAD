import Foundation
import CoreGraphics

struct RectangleShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var origin: CGPoint
    var size: CGSize
    var cornerRadius: CGFloat
    var stroke: StrokeStyle
    var isLocked: Bool = false

    init(id: UUID = UUID(), origin: CGPoint, size: CGSize, cornerRadius: CGFloat = 0, stroke: StrokeStyle = .default) {
        self.id = id
        self.origin = origin
        self.size = size
        self.cornerRadius = cornerRadius
        self.stroke = stroke
    }

    init(id: UUID = UUID(), from: CGPoint, to: CGPoint, cornerRadius: CGFloat = 0, stroke: StrokeStyle = .default) {
        self.id = id
        self.origin = CGPoint(x: min(from.x, to.x), y: min(from.y, to.y))
        self.size = CGSize(width: abs(to.x - from.x), height: abs(to.y - from.y))
        self.cornerRadius = cornerRadius
        self.stroke = stroke
    }

    var boundingBox: CGRect {
        CGRect(origin: origin, size: size)
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let rect = boundingBox
        let expanded = rect.insetBy(dx: -tolerance, dy: -tolerance)
        let shrunk = rect.insetBy(dx: tolerance, dy: tolerance)
        return expanded.contains(point) && !shrunk.contains(point)
    }

    mutating func translate(by delta: CGPoint) {
        origin = origin + delta
    }
}
