import Foundation
import CoreGraphics

enum Intersection {
    /// Find intersection point of two line segments. Returns nil if they don't intersect.
    static func lineLineIntersection(
        a1: CGPoint, a2: CGPoint,
        b1: CGPoint, b2: CGPoint
    ) -> CGPoint? {
        let d1 = CGPoint(x: a2.x - a1.x, y: a2.y - a1.y)
        let d2 = CGPoint(x: b2.x - b1.x, y: b2.y - b1.y)

        let cross = d1.x * d2.y - d1.y * d2.x
        guard abs(cross) > 1e-10 else { return nil } // parallel

        let d = CGPoint(x: b1.x - a1.x, y: b1.y - a1.y)
        let t = (d.x * d2.y - d.y * d2.x) / cross
        let u = (d.x * d1.y - d.y * d1.x) / cross

        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }

        return CGPoint(x: a1.x + t * d1.x, y: a1.y + t * d1.y)
    }

    /// Find intersection points of a line segment with a circle.
    static func lineCircleIntersection(
        lineStart: CGPoint, lineEnd: CGPoint,
        center: CGPoint, radius: CGFloat
    ) -> [CGPoint] {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let fx = lineStart.x - center.x
        let fy = lineStart.y - center.y

        let a = dx * dx + dy * dy
        let b = 2 * (fx * dx + fy * dy)
        let c = fx * fx + fy * fy - radius * radius

        var discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return [] }
        discriminant = sqrt(discriminant)

        var results: [CGPoint] = []
        for sign in [-1.0, 1.0] {
            let t = (-b + sign * discriminant) / (2 * a)
            if t >= 0 && t <= 1 {
                results.append(CGPoint(x: lineStart.x + t * dx, y: lineStart.y + t * dy))
            }
        }
        return results
    }

    /// Find intersection points of two circles.
    static func circleCircleIntersection(
        c1: CGPoint, r1: CGFloat,
        c2: CGPoint, r2: CGFloat
    ) -> [CGPoint] {
        let d = c1.distance(to: c2)
        guard d > 1e-10 else { return [] }
        guard d <= r1 + r2, d >= abs(r1 - r2) else { return [] }

        let a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
        let hSq = r1 * r1 - a * a
        guard hSq >= 0 else { return [] }
        let h = sqrt(hSq)

        let px = c1.x + a * (c2.x - c1.x) / d
        let py = c1.y + a * (c2.y - c1.y) / d

        if h < 1e-10 {
            return [CGPoint(x: px, y: py)]
        }

        let ox = h * (c2.y - c1.y) / d
        let oy = h * (c2.x - c1.x) / d

        return [
            CGPoint(x: px + ox, y: py - oy),
            CGPoint(x: px - ox, y: py + oy)
        ]
    }
}
