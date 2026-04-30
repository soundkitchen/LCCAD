import Foundation
import CoreGraphics

struct ArcShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var center: CGPoint
    var radius: CGFloat
    var startAngle: CGFloat  // radians
    var endAngle: CGFloat    // radians
    var clockwise: Bool = false
    var stroke: StrokeStyle
    var isLocked: Bool = false

    init(id: UUID = UUID(), center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool = false, stroke: StrokeStyle = .default) {
        self.id = id
        self.center = center
        self.radius = radius
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.clockwise = clockwise
        self.stroke = stroke
    }

    var boundingBox: CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// Tight bbox around the actual visible arc — endpoints plus any of the four
    /// cardinal-direction extrema (0, π/2, π, 3π/2) that lie within the arc's span.
    /// Used for placing mirror copies flush against the visible edge.
    var visualBoundingBox: CGRect {
        var pts: [CGPoint] = [startPoint, endPoint]
        for cardinal in [CGFloat(0), .pi / 2, .pi, 3 * .pi / 2] {
            if isAngleInArc(cardinal) {
                pts.append(CGPoint(
                    x: center.x + radius * cos(cardinal),
                    y: center.y + radius * sin(cardinal)
                ))
            }
        }
        var minX = pts[0].x, minY = pts[0].y
        var maxX = pts[0].x, maxY = pts[0].y
        for p in pts.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var startPoint: CGPoint {
        CGPoint(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle))
    }

    var endPoint: CGPoint {
        CGPoint(x: center.x + radius * cos(endAngle), y: center.y + radius * sin(endAngle))
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let dist = point.distance(to: center)
        guard abs(dist - radius) <= tolerance else { return false }

        let angle = atan2(point.y - center.y, point.x - center.x)
        return isAngleInArc(angle)
    }

    mutating func translate(by delta: CGPoint) {
        center = center + delta
    }

    mutating func mirror(axis: MirrorAxis) {
        center = center.mirrored(across: axis)
        switch axis {
        case .vertical:
            startAngle = .pi - startAngle
            endAngle = .pi - endAngle
        case .horizontal:
            startAngle = -startAngle
            endAngle = -endAngle
        }
        clockwise.toggle()
    }

    // MARK: - Parameterization

    var angleSpan: CGFloat {
        if clockwise {
            var span = startAngle - endAngle
            if span <= 0 { span += 2 * .pi }
            return span
        } else {
            var span = endAngle - startAngle
            if span <= 0 { span += 2 * .pi }
            return span
        }
    }

    func angleAtParameter(_ t: CGFloat) -> CGFloat {
        if clockwise {
            return startAngle - t * angleSpan
        } else {
            return startAngle + t * angleSpan
        }
    }

    func pointAtParameter(_ t: CGFloat) -> CGPoint {
        let a = angleAtParameter(t)
        return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    }

    /// Returns t ∈ [0, 1] if the angle falls within this arc, nil otherwise.
    func parameterForAngle(_ angle: CGFloat) -> CGFloat? {
        let norm = normalizeAngle(angle)
        let start = normalizeAngle(startAngle)

        if clockwise {
            var diff = start - norm
            if diff < 0 { diff += 2 * .pi }
            let t = diff / angleSpan
            return (t >= -1e-9 && t <= 1 + 1e-9) ? max(0, min(1, t)) : nil
        } else {
            var diff = norm - start
            if diff < 0 { diff += 2 * .pi }
            let t = diff / angleSpan
            return (t >= -1e-9 && t <= 1 + 1e-9) ? max(0, min(1, t)) : nil
        }
    }

    func isAngleInArc(_ angle: CGFloat) -> Bool {
        let a = normalizeAngle(angle)
        let s = normalizeAngle(startAngle)
        let e = normalizeAngle(endAngle)

        if clockwise {
            // Clockwise: from start going clockwise (decreasing angle) to end
            if s >= e {
                return a <= s && a >= e
            } else {
                return a <= s || a >= e
            }
        } else {
            // Counter-clockwise: from start going counter-clockwise (increasing angle) to end
            if s <= e {
                return a >= s && a <= e
            } else {
                return a >= s || a <= e
            }
        }
    }

    func normalizeAngle(_ angle: CGFloat) -> CGFloat {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return a
    }
}
