import Foundation
import CoreGraphics

/// Rounds the corner where two segments meet, replacing the sharp corner
/// with a circular arc of specified radius (fillet).
enum BevelTool {
    struct BevelResult {
        let line1: LineShape
        let line2: LineShape
        let arc: ArcShape
    }

    /// Pure-geometry description of a corner fillet, independent of any shape type.
    /// `tangentPrev` / `tangentNext` are where the arc meets the two straight legs.
    struct CornerFillet {
        let tangentPrev: CGPoint   // tangent point on the corner→prev leg
        let tangentNext: CGPoint   // tangent point on the corner→next leg
        let center: CGPoint
        let radius: CGFloat
        let startAngle: CGFloat    // angle of tangentPrev around center
        let endAngle: CGFloat      // angle of tangentNext around center
        /// Sweep direction (start→end) that traces the *minor* arc — the actual
        /// fillet. A fillet always spans < 180°, so the shorter arc is correct.
        let clockwise: Bool
    }

    /// Core fillet math: round the corner at `corner` formed by the two legs
    /// pointing towards `prev` and `next`. Returns nil if the legs are nearly
    /// parallel or the radius does not fit within either leg.
    static func filletCorner(prev: CGPoint, corner: CGPoint, next: CGPoint, radius: CGFloat) -> CornerFillet? {
        guard radius > 0 else { return nil }

        // Direction vectors from the corner towards each far end.
        let d1 = normalize(CGPoint(x: prev.x - corner.x, y: prev.y - corner.y))
        let d2 = normalize(CGPoint(x: next.x - corner.x, y: next.y - corner.y))

        // Half angle between the two legs.
        let dot = d1.x * d2.x + d1.y * d2.y
        let halfAngle = acos(max(-1, min(1, dot))) / 2
        guard halfAngle > 0.01 else { return nil } // Legs are nearly parallel

        // Distance from the corner to the tangent points.
        let tangentDist = radius / tan(halfAngle)
        let len1 = corner.distance(to: prev)
        let len2 = corner.distance(to: next)
        // Allow the fillet to consume a whole leg (tangentDist == leg): two fillets
        // on adjacent corners of one edge then meet exactly. The leftover zero-length
        // segment is dropped by the caller. A small epsilon absorbs float error.
        let epsilon: CGFloat = 1e-6
        guard tangentDist <= len1 + epsilon, tangentDist <= len2 + epsilon else { return nil } // Radius too large

        let t1 = CGPoint(x: corner.x + d1.x * tangentDist, y: corner.y + d1.y * tangentDist)
        let t2 = CGPoint(x: corner.x + d2.x * tangentDist, y: corner.y + d2.y * tangentDist)

        // Arc center lies along the bisector.
        let bisector = normalize(CGPoint(x: d1.x + d2.x, y: d1.y + d2.y))
        let centerDist = radius / sin(halfAngle)
        let center = CGPoint(x: corner.x + bisector.x * centerDist, y: corner.y + bisector.y * centerDist)

        let startAngle = atan2(t1.y - center.y, t1.x - center.x)
        let endAngle = atan2(t2.y - center.y, t2.x - center.x)

        // Pick the direction that traces the shorter (minor) arc start→end. The
        // counter-clockwise span > 180° means going clockwise is the short way.
        var ccwSpan = endAngle - startAngle
        while ccwSpan < 0 { ccwSpan += 2 * .pi }
        while ccwSpan >= 2 * .pi { ccwSpan -= 2 * .pi }
        let clockwise = ccwSpan > .pi

        return CornerFillet(tangentPrev: t1, tangentNext: t2,
                            center: center, radius: radius,
                            startAngle: startAngle, endAngle: endAngle,
                            clockwise: clockwise)
    }

    /// Bevel (round) the corner formed by two connected lines.
    /// The lines must share an endpoint (within tolerance).
    static func bevel(line1: LineShape, line2: LineShape, radius: CGFloat, tolerance: CGFloat = 0.5) -> BevelResult? {
        // Determine shared endpoint
        let (shared, end1, end2): (CGPoint, CGPoint, CGPoint)
        if line1.endPoint.distance(to: line2.startPoint) < tolerance {
            shared = line1.endPoint
            end1 = line1.startPoint
            end2 = line2.endPoint
        } else if line1.endPoint.distance(to: line2.endPoint) < tolerance {
            shared = line1.endPoint
            end1 = line1.startPoint
            end2 = line2.startPoint
        } else if line1.startPoint.distance(to: line2.startPoint) < tolerance {
            shared = line1.startPoint
            end1 = line1.endPoint
            end2 = line2.endPoint
        } else if line1.startPoint.distance(to: line2.endPoint) < tolerance {
            shared = line1.startPoint
            end1 = line1.endPoint
            end2 = line2.startPoint
        } else {
            return nil // Lines don't share an endpoint
        }

        guard let fillet = filletCorner(prev: end1, corner: shared, next: end2, radius: radius) else {
            return nil
        }

        // New shortened lines + the fillet arc.
        let newLine1 = LineShape(start: end1, end: fillet.tangentPrev, stroke: line1.stroke)
        let newLine2 = LineShape(start: fillet.tangentNext, end: end2, stroke: line2.stroke)
        let arc = ArcShape(center: fillet.center, radius: fillet.radius,
                           startAngle: fillet.startAngle, endAngle: fillet.endAngle,
                           clockwise: fillet.clockwise, stroke: line1.stroke)

        return BevelResult(line1: newLine1, line2: newLine2, arc: arc)
    }

    /// Approximate the minor circular arc from `from` to `to` (both on the circle
    /// of `center` / `radius`) with a single cubic Bézier segment. Returns the two
    /// interior control points so the fillet can be inserted into a Bézier path
    /// without disconnecting it. Accurate for sweeps up to ~90°, good enough up to
    /// ~120° which is the practical range for leather-pattern corners.
    static func arcToCubicControlPoints(from: CGPoint, to: CGPoint, center: CGPoint, radius: CGFloat) -> (controlOut: CGPoint, controlIn: CGPoint) {
        // Sweep angle (unsigned) between the two radii.
        let a0 = atan2(from.y - center.y, from.x - center.x)
        let a1 = atan2(to.y - center.y, to.x - center.x)
        var sweep = a1 - a0
        while sweep <= -CGFloat.pi { sweep += 2 * .pi }
        while sweep > CGFloat.pi { sweep -= 2 * .pi }

        // Magnitude only — the travel direction is carried by `sign` below, so
        // keeping `handle` positive avoids cancelling the direction twice.
        let handle = (4.0 / 3.0) * tan(abs(sweep) / 4) * radius

        // Unit tangents in the travel direction: perpendicular to each radius,
        // rotated by +90° times the sign of the sweep.
        let sign: CGFloat = sweep >= 0 ? 1 : -1
        let rFrom = normalize(CGPoint(x: from.x - center.x, y: from.y - center.y))
        let rTo = normalize(CGPoint(x: to.x - center.x, y: to.y - center.y))
        let tanFrom = CGPoint(x: -rFrom.y * sign, y: rFrom.x * sign)
        let tanTo = CGPoint(x: -rTo.y * sign, y: rTo.x * sign)

        let controlOut = CGPoint(x: from.x + tanFrom.x * handle, y: from.y + tanFrom.y * handle)
        let controlIn = CGPoint(x: to.x - tanTo.x * handle, y: to.y - tanTo.y * handle)
        return (controlOut, controlIn)
    }

    private static func normalize(_ v: CGPoint) -> CGPoint {
        let len = sqrt(v.x * v.x + v.y * v.y)
        guard len > 0 else { return .zero }
        return CGPoint(x: v.x / len, y: v.y / len)
    }
}
