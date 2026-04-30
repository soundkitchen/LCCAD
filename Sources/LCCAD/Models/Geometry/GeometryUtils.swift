import Foundation
import CoreGraphics

// MARK: - Units

enum LengthUnit: String, Codable, Equatable, CaseIterable {
    case millimeters = "mm"
    case inches = "inch"

    var abbreviation: String { rawValue }

    func toMillimeters(_ value: CGFloat) -> CGFloat {
        switch self {
        case .millimeters: return value
        case .inches: return value * 25.4
        }
    }

    func fromMillimeters(_ value: CGFloat) -> CGFloat {
        switch self {
        case .millimeters: return value
        case .inches: return value / 25.4
        }
    }
}

// MARK: - CGPoint extensions

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = other.x - x
        let dy = other.y - y
        return sqrt(dx * dx + dy * dy)
    }

    func midpoint(to other: CGPoint) -> CGPoint {
        CGPoint(x: (x + other.x) / 2, y: (y + other.y) / 2)
    }

    func angle(to other: CGPoint) -> CGFloat {
        atan2(other.y - y, other.x - x)
    }

    func offset(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    func mirrored(across axis: MirrorAxis) -> CGPoint {
        switch axis {
        case .vertical(let x):   return CGPoint(x: 2 * x - self.x, y: self.y)
        case .horizontal(let y): return CGPoint(x: self.x, y: 2 * y - self.y)
        }
    }
}

// MARK: - CGRect extensions

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    init(center: CGPoint, size: CGSize) {
        self.init(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    init(from: CGPoint, to: CGPoint) {
        let x = min(from.x, to.x)
        let y = min(from.y, to.y)
        let w = abs(to.x - from.x)
        let h = abs(to.y - from.y)
        self.init(x: x, y: y, width: w, height: h)
    }
}
