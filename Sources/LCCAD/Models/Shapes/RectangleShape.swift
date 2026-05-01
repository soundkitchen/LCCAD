import Foundation
import CoreGraphics

struct RectangleShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var origin: CGPoint
    var size: CGSize
    var cornerRadius: CGFloat
    var rotation: CGFloat = 0  // radians, applied around the unrotated center
    var stroke: StrokeStyle
    var isLocked: Bool = false

    init(id: UUID = UUID(), origin: CGPoint, size: CGSize, cornerRadius: CGFloat = 0, rotation: CGFloat = 0, stroke: StrokeStyle = .default) {
        self.id = id
        self.origin = origin
        self.size = size
        self.cornerRadius = cornerRadius
        self.rotation = rotation
        self.stroke = stroke
    }

    init(id: UUID = UUID(), from: CGPoint, to: CGPoint, cornerRadius: CGFloat = 0, stroke: StrokeStyle = .default) {
        self.id = id
        self.origin = CGPoint(x: min(from.x, to.x), y: min(from.y, to.y))
        self.size = CGSize(width: abs(to.x - from.x), height: abs(to.y - from.y))
        self.cornerRadius = cornerRadius
        self.stroke = stroke
    }

    enum CodingKeys: String, CodingKey {
        case id, origin, size, cornerRadius, rotation, stroke, isLocked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        origin = try c.decode(CGPoint.self, forKey: .origin)
        size = try c.decode(CGSize.self, forKey: .size)
        cornerRadius = try c.decode(CGFloat.self, forKey: .cornerRadius)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        stroke = try c.decode(StrokeStyle.self, forKey: .stroke)
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }

    /// Center of the unrotated rectangle. Rotation pivots around this point.
    var unrotatedCenter: CGPoint {
        CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    /// 4 corners of the rectangle in world space, after rotation is applied.
    var rotatedCorners: [CGPoint] {
        let topLeft = origin
        let topRight = CGPoint(x: origin.x + size.width, y: origin.y)
        let bottomRight = CGPoint(x: origin.x + size.width, y: origin.y + size.height)
        let bottomLeft = CGPoint(x: origin.x, y: origin.y + size.height)
        let corners = [topLeft, topRight, bottomRight, bottomLeft]
        guard rotation != 0 else { return corners }
        let c = unrotatedCenter
        return corners.map { $0.rotated(around: c, angle: rotation) }
    }

    var boundingBox: CGRect {
        guard rotation != 0 else { return CGRect(origin: origin, size: size) }
        let pts = rotatedCorners
        var minX = pts[0].x, minY = pts[0].y
        var maxX = pts[0].x, maxY = pts[0].y
        for p in pts.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let testPoint = rotation == 0
            ? point
            : point.rotated(around: unrotatedCenter, angle: -rotation)
        let rect = CGRect(origin: origin, size: size)
        let expanded = rect.insetBy(dx: -tolerance, dy: -tolerance)
        let shrunk = rect.insetBy(dx: tolerance, dy: tolerance)
        return expanded.contains(testPoint) && !shrunk.contains(testPoint)
    }

    mutating func translate(by delta: CGPoint) {
        origin = origin + delta
    }

    mutating func mirror(axis: MirrorAxis) {
        let p1 = origin.mirrored(across: axis)
        let p2 = CGPoint(x: origin.x + size.width, y: origin.y + size.height).mirrored(across: axis)
        origin = CGPoint(x: min(p1.x, p2.x), y: min(p1.y, p2.y))
        size = CGSize(width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
        rotation = -rotation
    }

    mutating func rotate(around pivot: CGPoint, angle: CGFloat) {
        let oldCenter = unrotatedCenter
        let newCenter = oldCenter.rotated(around: pivot, angle: angle)
        origin = CGPoint(x: newCenter.x - size.width / 2, y: newCenter.y - size.height / 2)
        rotation += angle
    }
}
