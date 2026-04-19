import Foundation
import CoreGraphics

/// Rounds the corner where two lines meet, replacing the sharp corner
/// with a circular arc of specified radius.
enum BevelTool {
    struct BevelResult {
        let line1: LineShape
        let line2: LineShape
        let arc: ArcShape
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

        // Direction vectors from shared point
        let d1 = normalize(CGPoint(x: end1.x - shared.x, y: end1.y - shared.y))
        let d2 = normalize(CGPoint(x: end2.x - shared.x, y: end2.y - shared.y))

        // Half angle between the two lines
        let dot = d1.x * d2.x + d1.y * d2.y
        let halfAngle = acos(max(-1, min(1, dot))) / 2

        guard halfAngle > 0.01 else { return nil } // Lines are nearly parallel

        // Distance from shared point to tangent points
        let tangentDist = radius / tan(halfAngle)
        let len1 = shared.distance(to: end1)
        let len2 = shared.distance(to: end2)
        guard tangentDist < len1, tangentDist < len2 else { return nil } // Radius too large

        // Tangent points
        let t1 = CGPoint(x: shared.x + d1.x * tangentDist, y: shared.y + d1.y * tangentDist)
        let t2 = CGPoint(x: shared.x + d2.x * tangentDist, y: shared.y + d2.y * tangentDist)

        // Arc center: along the bisector
        let bisector = normalize(CGPoint(x: d1.x + d2.x, y: d1.y + d2.y))
        let centerDist = radius / sin(halfAngle)
        let arcCenter = CGPoint(x: shared.x + bisector.x * centerDist, y: shared.y + bisector.y * centerDist)

        // Arc angles
        let startAngle = atan2(t1.y - arcCenter.y, t1.x - arcCenter.x)
        let endAngle = atan2(t2.y - arcCenter.y, t2.x - arcCenter.x)

        // New shortened lines
        let newLine1 = LineShape(start: end1, end: t1, stroke: line1.stroke)
        let newLine2 = LineShape(start: t2, end: end2, stroke: line2.stroke)
        let arc = ArcShape(center: arcCenter, radius: radius, startAngle: startAngle, endAngle: endAngle, stroke: line1.stroke)

        return BevelResult(line1: newLine1, line2: newLine2, arc: arc)
    }

    private static func normalize(_ v: CGPoint) -> CGPoint {
        let len = sqrt(v.x * v.x + v.y * v.y)
        guard len > 0 else { return .zero }
        return CGPoint(x: v.x / len, y: v.y / len)
    }
}
