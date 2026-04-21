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

// MARK: - Shape Protocol

protocol Shape: Identifiable, Codable, Sendable {
    var id: UUID { get }
    var stroke: StrokeStyle { get set }
    var isLocked: Bool { get set }

    /// Bounding box in world coordinates (mm)
    var boundingBox: CGRect { get }

    /// Hit test: is the given point (world coords) close enough to select this shape?
    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool

    /// Move the shape by a delta
    mutating func translate(by delta: CGPoint)
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

    var id: UUID {
        switch self {
        case .line(let s): return s.id
        case .rectangle(let s): return s.id
        case .ellipse(let s): return s.id
        case .arc(let s): return s.id
        case .dot(let s): return s.id
        case .bezier(let s): return s.id
        case .text(let s): return s.id
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
        }
    }
}
