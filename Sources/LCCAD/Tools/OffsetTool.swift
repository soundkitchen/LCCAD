import Foundation
import CoreGraphics

/// Creates a parallel copy of a line at a specified offset distance.
/// This is essential for generating stitch lines from edges (e.g., 3mm inset).
enum OffsetTool {
    /// Offset a line by a perpendicular distance.
    static func offsetLine(_ line: LineShape, distance: CGFloat) -> LineShape {
        let dx = line.endPoint.x - line.startPoint.x
        let dy = line.endPoint.y - line.startPoint.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return line }

        // Perpendicular unit vector (left side)
        let nx = -dy / length * distance
        let ny = dx / length * distance

        return LineShape(
            start: CGPoint(x: line.startPoint.x + nx, y: line.startPoint.y + ny),
            end: CGPoint(x: line.endPoint.x + nx, y: line.endPoint.y + ny),
            stroke: line.stroke
        )
    }

    /// Offset a rectangle inward or outward by a distance.
    static func offsetRectangle(_ rect: RectangleShape, distance: CGFloat) -> RectangleShape {
        let inset = distance
        return RectangleShape(
            origin: CGPoint(x: rect.origin.x + inset, y: rect.origin.y + inset),
            size: CGSize(width: max(0, rect.size.width - inset * 2), height: max(0, rect.size.height - inset * 2)),
            cornerRadius: max(0, rect.cornerRadius - inset),
            rotation: rect.rotation,
            stroke: rect.stroke
        )
    }

    /// Offset an ellipse by changing radii.
    static func offsetEllipse(_ ellipse: EllipseShape, distance: CGFloat) -> EllipseShape {
        return EllipseShape(
            center: ellipse.center,
            radiusX: max(0, ellipse.radiusX - distance),
            radiusY: max(0, ellipse.radiusY - distance),
            stroke: ellipse.stroke
        )
    }

    /// Offset an arc by adjusting its radius.
    /// Positive distance = inward (smaller radius), negative = outward (larger radius).
    /// Returns nil if the resulting radius would be zero or negative.
    static func offsetArc(_ arc: ArcShape, distance: CGFloat) -> ArcShape? {
        let newRadius = arc.radius - distance
        guard newRadius > 0 else { return nil }
        return ArcShape(
            center: arc.center,
            radius: newRadius,
            startAngle: arc.startAngle,
            endAngle: arc.endAngle,
            clockwise: arc.clockwise,
            stroke: arc.stroke
        )
    }

    // MARK: - Bezier Offset (Tiller-Hanson + Adaptive Subdivision)

    /// Offset a Bezier curve by a perpendicular distance.
    /// Uses Tiller-Hanson method with adaptive subdivision for accuracy.
    static func offsetBezier(_ bezier: BezierShape, distance: CGFloat) -> BezierShape {
        guard bezier.points.count >= 2 else { return bezier }

        let segmentCount = bezier.isClosed ? bezier.points.count : bezier.points.count - 1
        var resultPoints: [BezierPoint] = []

        for i in 0..<segmentCount {
            let j = (i + 1) % bezier.points.count
            let p0 = bezier.points[i].point
            let c1 = bezier.points[i].controlOut
            let c2 = bezier.points[j].controlIn
            let p3 = bezier.points[j].point

            let segmentPoints = subdivideAndOffset(
                p0: p0, c1: c1, c2: c2, p3: p3,
                distance: distance, tolerance: 0.1, maxDepth: 6
            )

            if resultPoints.isEmpty {
                resultPoints.append(contentsOf: segmentPoints)
            } else {
                // Skip the first point of subsequent segments (shared with previous segment's last point)
                // but adopt its controlIn for the junction
                if let last = resultPoints.last, !segmentPoints.isEmpty {
                    resultPoints[resultPoints.count - 1] = BezierPoint(
                        point: last.point,
                        controlIn: last.controlIn,
                        controlOut: segmentPoints[0].controlOut
                    )
                    resultPoints.append(contentsOf: segmentPoints.dropFirst())
                }
            }
        }

        // For closed curves, merge the last point's controlOut into the first point
        if bezier.isClosed && resultPoints.count >= 2 {
            let lastOut = resultPoints[resultPoints.count - 1].controlOut
            resultPoints[0] = BezierPoint(
                point: resultPoints[0].point,
                controlIn: lastOut,
                controlOut: resultPoints[0].controlOut
            )
            resultPoints.removeLast()
        }

        return BezierShape(
            points: resultPoints,
            isClosed: bezier.isClosed,
            stroke: bezier.stroke
        )
    }

    /// Recursively subdivide a cubic segment and offset using Tiller-Hanson.
    private static func subdivideAndOffset(
        p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint,
        distance: CGFloat, tolerance: CGFloat, maxDepth: Int
    ) -> [BezierPoint] {
        let flatness = cubicFlatness(p0: p0, c1: c1, c2: c2, p3: p3)

        if flatness < tolerance || maxDepth <= 0 {
            let (op0, oc1, oc2, op3) = offsetCubicTillerHanson(
                p0: p0, c1: c1, c2: c2, p3: p3, distance: distance
            )
            return [
                BezierPoint(point: op0, controlIn: op0, controlOut: oc1),
                BezierPoint(point: op3, controlIn: oc2, controlOut: op3),
            ]
        }

        // De Casteljau split at t = 0.5
        let (left, right) = splitCubicAt05(p0: p0, c1: c1, c2: c2, p3: p3)

        let leftPoints = subdivideAndOffset(
            p0: left.0, c1: left.1, c2: left.2, p3: left.3,
            distance: distance, tolerance: tolerance, maxDepth: maxDepth - 1
        )
        let rightPoints = subdivideAndOffset(
            p0: right.0, c1: right.1, c2: right.2, p3: right.3,
            distance: distance, tolerance: tolerance, maxDepth: maxDepth - 1
        )

        // Merge: left points + right points (skip duplicate midpoint)
        var merged = leftPoints
        if let last = merged.last, !rightPoints.isEmpty {
            merged[merged.count - 1] = BezierPoint(
                point: last.point,
                controlIn: last.controlIn,
                controlOut: rightPoints[0].controlOut
            )
            merged.append(contentsOf: rightPoints.dropFirst())
        }
        return merged
    }

    /// Tiller-Hanson offset: offset the three legs of the control polygon and find intersections.
    private static func offsetCubicTillerHanson(
        p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint,
        distance: CGFloat
    ) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        // Offset each leg of the control polygon
        let (l1a, l1b) = offsetSegment(a: p0, b: c1, distance: distance)
        let (l2a, l2b) = offsetSegment(a: c1, b: c2, distance: distance)
        let (l3a, l3b) = offsetSegment(a: c2, b: p3, distance: distance)

        // New control points are intersections of adjacent offset legs
        let newC1 = lineLineIntersectionUnbounded(a1: l1a, a2: l1b, b1: l2a, b2: l2b) ?? l1b
        let newC2 = lineLineIntersectionUnbounded(a1: l2a, a2: l2b, b1: l3a, b2: l3b) ?? l3a

        return (l1a, newC1, newC2, l3b)
    }

    /// Offset a line segment by distance along its left-side perpendicular.
    private static func offsetSegment(a: CGPoint, b: CGPoint, distance: CGFloat) -> (CGPoint, CGPoint) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 1e-10 else {
            // Degenerate segment: return original points
            return (a, b)
        }
        let nx = -dy / len * distance
        let ny = dx / len * distance
        return (
            CGPoint(x: a.x + nx, y: a.y + ny),
            CGPoint(x: b.x + nx, y: b.y + ny)
        )
    }

    /// Unbounded line-line intersection (not restricted to segment [0,1]).
    private static func lineLineIntersectionUnbounded(
        a1: CGPoint, a2: CGPoint, b1: CGPoint, b2: CGPoint
    ) -> CGPoint? {
        let d1x = a2.x - a1.x
        let d1y = a2.y - a1.y
        let d2x = b2.x - b1.x
        let d2y = b2.y - b1.y
        let cross = d1x * d2y - d1y * d2x
        guard abs(cross) > 1e-10 else { return nil }  // Parallel
        let dx = b1.x - a1.x
        let dy = b1.y - a1.y
        let t = (dx * d2y - dy * d2x) / cross
        return CGPoint(x: a1.x + t * d1x, y: a1.y + t * d1y)
    }

    /// Max distance of control points from the chord p0→p3.
    private static func cubicFlatness(p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint) -> CGFloat {
        let d1 = pointToLineDistance(point: c1, lineA: p0, lineB: p3)
        let d2 = pointToLineDistance(point: c2, lineA: p0, lineB: p3)
        return max(d1, d2)
    }

    /// Perpendicular distance from a point to a line defined by two points.
    private static func pointToLineDistance(point: CGPoint, lineA: CGPoint, lineB: CGPoint) -> CGFloat {
        let dx = lineB.x - lineA.x
        let dy = lineB.y - lineA.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 1e-20 else {
            return point.distance(to: lineA)
        }
        let cross = abs((point.x - lineA.x) * dy - (point.y - lineA.y) * dx)
        return cross / sqrt(lenSq)
    }

    /// De Casteljau split at t = 0.5.
    private static func splitCubicAt05(
        p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint
    ) -> ((CGPoint, CGPoint, CGPoint, CGPoint), (CGPoint, CGPoint, CGPoint, CGPoint)) {
        let m01 = mid(p0, c1)
        let m12 = mid(c1, c2)
        let m23 = mid(c2, p3)
        let m012 = mid(m01, m12)
        let m123 = mid(m12, m23)
        let m0123 = mid(m012, m123)
        return (
            (p0, m01, m012, m0123),
            (m0123, m123, m23, p3)
        )
    }

    private static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }
}
