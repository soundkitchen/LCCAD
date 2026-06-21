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

    /// Axis-aligned bounds ignoring rotation. Used by renderers that draw the
    /// ellipse in local space and apply rotation separately (mirrors the way
    /// RectangleShape keeps its raw origin/size distinct from `boundingBox`).
    var unrotatedBounds: CGRect {
        CGRect(x: center.x - radiusX, y: center.y - radiusY, width: radiusX * 2, height: radiusY * 2)
    }

    var boundingBox: CGRect {
        guard rotation != 0 else { return unrotatedBounds }
        // Closed-form AABB of a rotated ellipse: the parametric extremes in x
        // and y have amplitudes √(rx²cos²θ + ry²sin²θ) and √(rx²sin²θ + ry²cos²θ).
        let c = cos(rotation)
        let s = sin(rotation)
        let hx = (radiusX * radiusX * c * c + radiusY * radiusY * s * s).squareRoot()
        let hy = (radiusX * radiusX * s * s + radiusY * radiusY * c * c).squareRoot()
        return CGRect(x: center.x - hx, y: center.y - hy, width: hx * 2, height: hy * 2)
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

    mutating func rotate(around pivot: CGPoint, angle: CGFloat) {
        center = center.rotated(around: pivot, angle: angle)
        rotation += angle
    }
}
