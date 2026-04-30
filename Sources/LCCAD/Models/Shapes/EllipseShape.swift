import Foundation
import CoreGraphics

struct EllipseShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var center: CGPoint
    var radiusX: CGFloat
    var radiusY: CGFloat
    var rotation: CGFloat = 0
    var stroke: StrokeStyle
    var isLocked: Bool = false

    init(id: UUID = UUID(), center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, stroke: StrokeStyle = .default) {
        self.id = id
        self.center = center
        self.radiusX = radiusX
        self.radiusY = radiusY
        self.stroke = stroke
    }

    var boundingBox: CGRect {
        CGRect(x: center.x - radiusX, y: center.y - radiusY, width: radiusX * 2, height: radiusY * 2)
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let dx = (point.x - center.x) / radiusX
        let dy = (point.y - center.y) / radiusY
        let normalizedDist = sqrt(dx * dx + dy * dy)
        let normalizedTolerance = tolerance / min(radiusX, radiusY)
        return abs(normalizedDist - 1.0) <= normalizedTolerance
    }

    mutating func translate(by delta: CGPoint) {
        center = center + delta
    }

    mutating func mirror(axis: MirrorAxis) {
        center = center.mirrored(across: axis)
        rotation = -rotation
    }
}
