import Foundation
import CoreGraphics

// MARK: - Dimension Kind

enum DimensionKind: String, Codable, Equatable, Sendable, CaseIterable {
    case aligned      // true distance along the start→end segment
    case horizontal   // horizontal (X) component only
    case vertical     // vertical (Y) component only

    var displayName: String {
        switch self {
        case .aligned: return "Aligned"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

// MARK: - Dimension Line Shape

/// An annotation measuring the distance between two points. The dimension line
/// is drawn parallel to the measured direction, offset perpendicular by `offset`
/// (signed; the sign chooses which side). The label is auto-computed from the
/// geometry in the document unit unless `labelOverride` is set.
struct DimensionLineShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var start: CGPoint          // first measured point (world mm)
    var end: CGPoint            // second measured point (world mm)
    var offset: CGFloat         // signed distance from the measured baseline to the dimension line (mm)
    var kind: DimensionKind
    var labelOverride: String?  // nil / empty = auto value
    var stroke: StrokeStyle
    var isLocked: Bool = false

    /// Annotation text height in world units (mm) — dimensions print at a real size.
    static let textHeight: CGFloat = 3.0
    /// Arrowhead length in world units (mm).
    static let arrowLength: CGFloat = 2.4

    init(id: UUID = UUID(), start: CGPoint, end: CGPoint, offset: CGFloat,
         kind: DimensionKind = .aligned, labelOverride: String? = nil, stroke: StrokeStyle = .default) {
        self.id = id
        self.start = start
        self.end = end
        self.offset = offset
        self.kind = kind
        self.labelOverride = labelOverride
        self.stroke = stroke
    }

    /// Build from three picked points: start, end, and a third point whose
    /// position determines the dimension line's offset and side.
    init(start: CGPoint, end: CGPoint, third: CGPoint, kind: DimensionKind, stroke: StrokeStyle = .default) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.kind = kind
        self.labelOverride = nil
        self.stroke = stroke
        self.offset = Self.offset(start: start, end: end, third: third, kind: kind)
    }

    /// Compute the signed offset implied by a third (placement) point.
    static func offset(start: CGPoint, end: CGPoint, third: CGPoint, kind: DimensionKind) -> CGFloat {
        switch kind {
        case .aligned:
            let dx = end.x - start.x, dy = end.y - start.y
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 1e-9 else { return third.y - start.y }
            // left-normal of the start→end direction
            let nx = -dy / len, ny = dx / len
            return (third.x - start.x) * nx + (third.y - start.y) * ny
        case .horizontal:
            return third.y - (start.y + end.y) / 2
        case .vertical:
            return third.x - (start.x + end.x) / 2
        }
    }

    // MARK: - Derived geometry

    /// Measured value in millimetres (the internal unit), per kind.
    var measuredValue: CGFloat {
        switch kind {
        case .aligned: return start.distance(to: end)
        case .horizontal: return abs(end.x - start.x)
        case .vertical: return abs(end.y - start.y)
        }
    }

    /// Unit left-normal of the start→end direction (used by `.aligned`).
    private var leftNormal: CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-9 else { return CGPoint(x: 0, y: 1) }
        return CGPoint(x: -dy / len, y: dx / len)
    }

    /// The two endpoints of the dimension line (the offset line carrying the arrows).
    var dimEndpoints: (CGPoint, CGPoint) {
        switch kind {
        case .aligned:
            let n = leftNormal
            return (start + n * offset, end + n * offset)
        case .horizontal:
            let y = (start.y + end.y) / 2 + offset
            return (CGPoint(x: start.x, y: y), CGPoint(x: end.x, y: y))
        case .vertical:
            let x = (start.x + end.x) / 2 + offset
            return (CGPoint(x: x, y: start.y), CGPoint(x: x, y: end.y))
        }
    }

    /// Midpoint of the dimension line — where the label is anchored.
    var labelAnchor: CGPoint {
        let (a, b) = dimEndpoints
        return a.midpoint(to: b)
    }

    /// Auto label text formatted in the given unit (one decimal place).
    func autoLabel(unit: LengthUnit) -> String {
        String(format: "%.1f", unit.fromMillimeters(measuredValue))
    }

    /// Final display text: the manual override if present, else the auto value.
    func displayLabel(unit: LengthUnit) -> String {
        if let labelOverride, !labelOverride.isEmpty { return labelOverride }
        return autoLabel(unit: unit)
    }

    // MARK: - Shape protocol

    var boundingBox: CGRect {
        let (a, b) = dimEndpoints
        let margin = Self.textHeight + Self.arrowLength
        let minX = min(start.x, end.x, a.x, b.x) - margin
        let minY = min(start.y, end.y, a.y, b.y) - margin
        let maxX = max(start.x, end.x, a.x, b.x) + margin
        let maxY = max(start.y, end.y, a.y, b.y) + margin
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let (a, b) = dimEndpoints
        // Grab targets: the dimension line and the two extension lines.
        return distanceToSegment(point, a, b) <= tolerance
            || distanceToSegment(point, start, a) <= tolerance
            || distanceToSegment(point, end, b) <= tolerance
    }

    mutating func translate(by delta: CGPoint) {
        start = start + delta
        end = end + delta
    }

    mutating func mirror(axis: MirrorAxis) {
        start = start.mirrored(across: axis)
        end = end.mirrored(across: axis)
        // The dimension-line side must flip to stay on the same visual side.
        switch (kind, axis) {
        case (.aligned, _): offset = -offset            // handedness flips on any mirror
        case (.horizontal, .horizontal): offset = -offset
        case (.vertical, .vertical): offset = -offset
        default: break
        }
    }

    mutating func rotate(around pivot: CGPoint, angle: CGFloat) {
        start = start.rotated(around: pivot, angle: angle)
        end = end.rotated(around: pivot, angle: angle)
        // `.aligned` keeps its perpendicular offset; `.horizontal`/`.vertical`
        // are re-derived axis-aligned through the rotated baseline (best effort —
        // dimension annotations are not normally rotated).
    }

    // MARK: - Helpers

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-12 { return p.distance(to: a) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = max(0, min(1, t))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return p.distance(to: proj)
    }
}
