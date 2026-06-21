import Foundation
import CoreGraphics

// MARK: - Line Style

enum LineStyle: String, Codable, Equatable, Sendable, CaseIterable {
    case solid      // 実線
    case dashed     // 破線
    case dotted     // 点線
    case dashDot    // 一点鎖線

    /// Dash pattern in world units (mm). nil means solid line.
    var dashPattern: [CGFloat]? {
        switch self {
        case .solid:   return nil
        case .dashed:  return [3, 2]
        case .dotted:  return [0.5, 1.5]
        case .dashDot: return [3, 1.5, 0.5, 1.5]
        }
    }

    var displayName: String {
        switch self {
        case .solid:   return "Solid"
        case .dashed:  return "Dashed"
        case .dotted:  return "Dotted"
        case .dashDot: return "Dash-Dot"
        }
    }

    /// DXF linetype name
    var dxfName: String {
        switch self {
        case .solid:   return "CONTINUOUS"
        case .dashed:  return "DASHED"
        case .dotted:  return "DOTTED"
        case .dashDot: return "DASHDOT"
        }
    }
}

// MARK: - Stroke Style

struct StrokeStyle: Codable, Equatable, Sendable {
    var color: CodableColor
    var width: CGFloat
    var lineStyle: LineStyle
    var dashPattern: [CGFloat]?

    /// Default stroke: thin line suitable for CAD patterns.
    /// Width is in world units (mm). At default zoom (3x), 0.25mm ≈ 0.75px → clamped to 1px.
    static let `default` = StrokeStyle(color: CodableColor(r: 0, g: 0, b: 0), width: 0.25)

    init(color: CodableColor, width: CGFloat, lineStyle: LineStyle = .solid) {
        self.color = color
        self.width = width
        self.lineStyle = lineStyle
        self.dashPattern = lineStyle.dashPattern
    }

    // Backward-compatible decoding: old files without lineStyle default to .solid
    enum CodingKeys: String, CodingKey {
        case color, width, lineStyle, dashPattern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decode(CodableColor.self, forKey: .color)
        width = try container.decode(CGFloat.self, forKey: .width)
        lineStyle = try container.decodeIfPresent(LineStyle.self, forKey: .lineStyle) ?? .solid
        dashPattern = try container.decodeIfPresent([CGFloat].self, forKey: .dashPattern)
        // If lineStyle was decoded as non-solid, derive dashPattern from it
        if lineStyle != .solid {
            dashPattern = lineStyle.dashPattern
        }
    }
}

// MARK: - Codable Color

struct CodableColor: Codable, Equatable, Sendable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    static let black = CodableColor(r: 0, g: 0, b: 0)
    static let white = CodableColor(r: 1, g: 1, b: 1)
    static let stitch = CodableColor(r: 0.831, g: 0.647, b: 0.455) // #D4A574
}

// MARK: - Mirror Axis

enum MirrorAxis: Sendable {
    case horizontal(y: CGFloat)  // 横軸（y 一定）→ 上下反転
    case vertical(x: CGFloat)    // 縦軸（x 一定）→ 左右反転
}

// MARK: - Shape Protocol

protocol Shape: Identifiable, Codable, Sendable {
    var id: UUID { get }
    var stroke: StrokeStyle { get set }
    var isLocked: Bool { get set }

    /// Bounding box in world coordinates (mm)
    var boundingBox: CGRect { get }

    /// Tight box around the visually rendered ink in world coordinates (mm).
    /// Differs from `boundingBox` for shapes whose `boundingBox` overshoots
    /// the visible curve (Bezier handles, Arc full-circle bounds). Used to
    /// place mirror copies flush against the visual edge.
    var visualBoundingBox: CGRect { get }

    /// Hit test: is the given point (world coords) close enough to select this shape?
    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool

    /// Move the shape by a delta
    mutating func translate(by delta: CGPoint)

    /// Reflect the shape across the given world-space axis
    mutating func mirror(axis: MirrorAxis)

    /// Rotate the shape around the given world-space point by `angle` radians (CCW positive).
    mutating func rotate(around center: CGPoint, angle: CGFloat)
}

extension Shape {
    var visualBoundingBox: CGRect { boundingBox }
}

// MARK: - AnyShape (type-erased wrapper for heterogeneous collections)

enum AnyShape: Codable, Identifiable, Equatable, Sendable {
    case line(LineShape)
    case rectangle(RectangleShape)
    case ellipse(EllipseShape)
    case arc(ArcShape)
    case dot(DotShape)
    case bezier(BezierShape)
    case text(TextShape)
    case dimensionLine(DimensionLineShape)
    case group(GroupShape)

    var id: UUID {
        switch self {
        case .line(let s): return s.id
        case .rectangle(let s): return s.id
        case .ellipse(let s): return s.id
        case .arc(let s): return s.id
        case .dot(let s): return s.id
        case .bezier(let s): return s.id
        case .text(let s): return s.id
        case .dimensionLine(let s): return s.id
        case .group(let s): return s.id
        }
    }

    var stroke: StrokeStyle {
        get {
            switch self {
            case .line(let s): return s.stroke
            case .rectangle(let s): return s.stroke
            case .ellipse(let s): return s.stroke
            case .arc(let s): return s.stroke
            case .dot(let s): return s.stroke
            case .bezier(let s): return s.stroke
            case .text(let s): return s.stroke
            case .dimensionLine(let s): return s.stroke
            case .group(let s): return s.stroke
            }
        }
        set {
            switch self {
            case .line(var s): s.stroke = newValue; self = .line(s)
            case .rectangle(var s): s.stroke = newValue; self = .rectangle(s)
            case .ellipse(var s): s.stroke = newValue; self = .ellipse(s)
            case .arc(var s): s.stroke = newValue; self = .arc(s)
            case .dot(var s): s.stroke = newValue; self = .dot(s)
            case .bezier(var s): s.stroke = newValue; self = .bezier(s)
            case .text(var s): s.stroke = newValue; self = .text(s)
            case .dimensionLine(var s): s.stroke = newValue; self = .dimensionLine(s)
            case .group(var s): s.stroke = newValue; self = .group(s)
            }
        }
    }

    var isLocked: Bool {
        get {
            switch self {
            case .line(let s): return s.isLocked
            case .rectangle(let s): return s.isLocked
            case .ellipse(let s): return s.isLocked
            case .arc(let s): return s.isLocked
            case .dot(let s): return s.isLocked
            case .bezier(let s): return s.isLocked
            case .text(let s): return s.isLocked
            case .dimensionLine(let s): return s.isLocked
            case .group(let s): return s.isLocked
            }
        }
        set {
            switch self {
            case .line(var s): s.isLocked = newValue; self = .line(s)
            case .rectangle(var s): s.isLocked = newValue; self = .rectangle(s)
            case .ellipse(var s): s.isLocked = newValue; self = .ellipse(s)
            case .arc(var s): s.isLocked = newValue; self = .arc(s)
            case .dot(var s): s.isLocked = newValue; self = .dot(s)
            case .bezier(var s): s.isLocked = newValue; self = .bezier(s)
            case .text(var s): s.isLocked = newValue; self = .text(s)
            case .dimensionLine(var s): s.isLocked = newValue; self = .dimensionLine(s)
            case .group(var s): s.isLocked = newValue; self = .group(s)
            }
        }
    }

    var boundingBox: CGRect {
        switch self {
        case .line(let s): return s.boundingBox
        case .rectangle(let s): return s.boundingBox
        case .ellipse(let s): return s.boundingBox
        case .arc(let s): return s.boundingBox
        case .dot(let s): return s.boundingBox
        case .bezier(let s): return s.boundingBox
        case .text(let s): return s.boundingBox
        case .dimensionLine(let s): return s.boundingBox
        case .group(let s): return s.boundingBox
        }
    }

    var visualBoundingBox: CGRect {
        switch self {
        case .line(let s): return s.visualBoundingBox
        case .rectangle(let s): return s.visualBoundingBox
        case .ellipse(let s): return s.visualBoundingBox
        case .arc(let s): return s.visualBoundingBox
        case .dot(let s): return s.visualBoundingBox
        case .bezier(let s): return s.visualBoundingBox
        case .text(let s): return s.visualBoundingBox
        case .dimensionLine(let s): return s.visualBoundingBox
        case .group(let s): return s.visualBoundingBox
        }
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        switch self {
        case .line(let s): return s.hitTest(point: point, tolerance: tolerance)
        case .rectangle(let s): return s.hitTest(point: point, tolerance: tolerance)
        case .ellipse(let s): return s.hitTest(point: point, tolerance: tolerance)
        case .arc(let s): return s.hitTest(point: point, tolerance: tolerance)
        case .dot(let s): return s.hitTest(point: point, tolerance: tolerance)
        case .bezier(let s): return s.hitTest(point: point, tolerance: tolerance)
        case .text(let s): return s.hitTest(point: point, tolerance: tolerance)
        case .dimensionLine(let s): return s.hitTest(point: point, tolerance: tolerance)
        case .group(let s): return s.hitTest(point: point, tolerance: tolerance)
        }
    }

    mutating func translate(by delta: CGPoint) {
        switch self {
        case .line(var s): s.translate(by: delta); self = .line(s)
        case .rectangle(var s): s.translate(by: delta); self = .rectangle(s)
        case .ellipse(var s): s.translate(by: delta); self = .ellipse(s)
        case .arc(var s): s.translate(by: delta); self = .arc(s)
        case .dot(var s): s.translate(by: delta); self = .dot(s)
        case .bezier(var s): s.translate(by: delta); self = .bezier(s)
        case .text(var s): s.translate(by: delta); self = .text(s)
        case .dimensionLine(var s): s.translate(by: delta); self = .dimensionLine(s)
        case .group(var s): s.translate(by: delta); self = .group(s)
        }
    }

    mutating func mirror(axis: MirrorAxis) {
        switch self {
        case .line(var s): s.mirror(axis: axis); self = .line(s)
        case .rectangle(var s): s.mirror(axis: axis); self = .rectangle(s)
        case .ellipse(var s): s.mirror(axis: axis); self = .ellipse(s)
        case .arc(var s): s.mirror(axis: axis); self = .arc(s)
        case .dot(var s): s.mirror(axis: axis); self = .dot(s)
        case .bezier(var s): s.mirror(axis: axis); self = .bezier(s)
        case .text(var s): s.mirror(axis: axis); self = .text(s)
        case .dimensionLine(var s): s.mirror(axis: axis); self = .dimensionLine(s)
        case .group(var s): s.mirror(axis: axis); self = .group(s)
        }
    }

    mutating func rotate(around center: CGPoint, angle: CGFloat) {
        switch self {
        case .line(var s): s.rotate(around: center, angle: angle); self = .line(s)
        case .rectangle(var s): s.rotate(around: center, angle: angle); self = .rectangle(s)
        case .ellipse(var s): s.rotate(around: center, angle: angle); self = .ellipse(s)
        case .arc(var s): s.rotate(around: center, angle: angle); self = .arc(s)
        case .dot(var s): s.rotate(around: center, angle: angle); self = .dot(s)
        case .bezier(var s): s.rotate(around: center, angle: angle); self = .bezier(s)
        case .text(var s): s.rotate(around: center, angle: angle); self = .text(s)
        case .dimensionLine(var s): s.rotate(around: center, angle: angle); self = .dimensionLine(s)
        case .group(var s): s.rotate(around: center, angle: angle); self = .group(s)
        }
    }
}
