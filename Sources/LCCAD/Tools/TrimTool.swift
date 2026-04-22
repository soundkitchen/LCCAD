import Foundation
import CoreGraphics

/// Trims a shape at intersection points with other shapes.
/// Clicking on a segment between two intersections **removes** that segment.
enum TrimTool {
    struct TrimResult {
        let replacements: [AnyShape]
    }

    private static let eps: CGFloat = 1e-6
    private static let sampleCount: Int = 64

    // MARK: - Public API

    /// Trim `shape` at its intersections with `others`, removing the segment under `clickPoint`.
    static func trim(shape: AnyShape, against others: [AnyShape], clickPoint: CGPoint) -> TrimResult? {
        switch shape {
        case .line, .arc, .bezier:
            return trimOpenCurve(shape: shape, against: others, clickPoint: clickPoint)
        case .rectangle(let rect):
            return trimRectangle(rect, against: others, clickPoint: clickPoint)
        case .ellipse(let ellipse):
            return trimEllipse(ellipse, against: others, clickPoint: clickPoint)
        case .dot, .text, .group:
            return nil
        }
    }

    // MARK: - Open Curves (Line, Arc, Bezier)

    private static func trimOpenCurve(shape: AnyShape, against others: [AnyShape], clickPoint: CGPoint) -> TrimResult? {
        let intersectionTs = findIntersectionTs(shape: shape, against: others, isClosed: false)
        guard !intersectionTs.isEmpty else { return nil }

        guard let clickT = projectPoint(clickPoint, onto: shape) else { return nil }

        let sorted = intersectionTs.sorted()

        var lowerBound: CGFloat = 0.0
        var upperBound: CGFloat = 1.0
        for t in sorted where t <= clickT + eps { lowerBound = t }
        for t in sorted where t >= clickT - eps { upperBound = t; break }

        lowerBound = max(0, lowerBound)
        upperBound = min(1, upperBound)
        guard upperBound - lowerBound > eps else { return nil }

        var replacements: [AnyShape] = []
        if lowerBound > eps {
            if let part = extractRange(from: shape, start: 0, end: lowerBound) {
                replacements.append(part)
            }
        }
        if upperBound < 1 - eps {
            if let part = extractRange(from: shape, start: upperBound, end: 1) {
                replacements.append(part)
            }
        }
        return TrimResult(replacements: replacements)
    }

    // MARK: - Rectangle (explode into edges, trim clicked edge)

    private static func trimRectangle(_ rect: RectangleShape, against others: [AnyShape], clickPoint: CGPoint) -> TrimResult? {
        let edges = rectEdges(rect)

        // Find closest edge to click
        guard let clickedIndex = edges.indices.min(by: {
            distanceToSegment(clickPoint, edges[$0].startPoint, edges[$0].endPoint) <
            distanceToSegment(clickPoint, edges[$1].startPoint, edges[$1].endPoint)
        }) else { return nil }

        let clickedEdge = edges[clickedIndex]

        // Find intersections on this edge with other shapes
        let intersectionTs = findIntersectionTs(
            shape: .line(clickedEdge), against: others, isClosed: false
        )
        guard !intersectionTs.isEmpty else { return nil }

        let clickT = projectPointOnLine(clickPoint, lineStart: clickedEdge.startPoint, lineEnd: clickedEdge.endPoint)
        let sorted = intersectionTs.sorted()

        var lowerBound: CGFloat = 0.0
        var upperBound: CGFloat = 1.0
        for t in sorted where t <= clickT + eps { lowerBound = t }
        for t in sorted where t >= clickT - eps { upperBound = t; break }
        guard upperBound - lowerBound > eps else { return nil }

        // Keep 3 untouched edges + remaining parts of the clicked edge
        var replacements: [AnyShape] = []
        for (i, edge) in edges.enumerated() where i != clickedIndex {
            replacements.append(.line(edge))
        }
        if lowerBound > eps {
            replacements.append(extractLineRange(clickedEdge, start: 0, end: lowerBound))
        }
        if upperBound < 1 - eps {
            replacements.append(extractLineRange(clickedEdge, start: upperBound, end: 1))
        }

        return TrimResult(replacements: replacements)
    }

    private static func rectEdges(_ rect: RectangleShape) -> [LineShape] {
        let o = rect.origin, s = rect.size
        let tl = o
        let tr = CGPoint(x: o.x + s.width, y: o.y)
        let br = CGPoint(x: o.x + s.width, y: o.y + s.height)
        let bl = CGPoint(x: o.x, y: o.y + s.height)
        return [
            LineShape(start: tl, end: tr, stroke: rect.stroke),
            LineShape(start: tr, end: br, stroke: rect.stroke),
            LineShape(start: br, end: bl, stroke: rect.stroke),
            LineShape(start: bl, end: tl, stroke: rect.stroke),
        ]
    }

    // MARK: - Ellipse (closed curve)

    private static func trimEllipse(_ ellipse: EllipseShape, against others: [AnyShape], clickPoint: CGPoint) -> TrimResult? {
        let shape = AnyShape.ellipse(ellipse)
        let intersectionTs = findIntersectionTs(shape: shape, against: others, isClosed: true)
        guard intersectionTs.count >= 2 else { return nil }

        let clickT = projectPointOnEllipse(clickPoint, ellipse: ellipse)
        let sorted = intersectionTs.sorted()
        let n = sorted.count

        // Find which gap between consecutive intersections the click falls in
        var clickGapIndex = n - 1 // default to the wrap-around gap
        for i in 0..<n {
            let gapStart = sorted[i]
            let gapEnd = sorted[(i + 1) % n]

            if gapStart < gapEnd {
                if clickT >= gapStart - eps && clickT <= gapEnd + eps {
                    clickGapIndex = i
                    break
                }
            } else {
                // Wrap-around gap
                if clickT >= gapStart - eps || clickT <= gapEnd + eps {
                    clickGapIndex = i
                    break
                }
            }
        }

        // Keep all gaps except the clicked one
        var replacements: [AnyShape] = []
        for i in 0..<n where i != clickGapIndex {
            let gapStart = sorted[i]
            let gapEnd = sorted[(i + 1) % n]
            if let part = extractEllipseRange(ellipse, start: gapStart, end: gapEnd) {
                replacements.append(part)
            }
        }

        return TrimResult(replacements: replacements)
    }

    private static func projectPointOnEllipse(_ point: CGPoint, ellipse: EllipseShape) -> CGFloat {
        let angle = atan2(
            (point.y - ellipse.center.y) / ellipse.radiusY,
            (point.x - ellipse.center.x) / ellipse.radiusX
        )
        var t = angle / (2 * .pi)
        if t < 0 { t += 1 }
        return t
    }

    private static func extractEllipseRange(_ ellipse: EllipseShape, start: CGFloat, end: CGFloat) -> AnyShape? {
        let startAngle = start * 2 * .pi
        let endAngle: CGFloat
        if end >= start {
            endAngle = end * 2 * .pi
        } else {
            // Wrapping: e.g. start=0.8, end=0.2 → endAngle = 0.2*2π (arc wraps through 0)
            endAngle = end * 2 * .pi
        }

        // For circles (equal radii), output ArcShape
        if abs(ellipse.radiusX - ellipse.radiusY) < 0.001 {
            return .arc(ArcShape(
                center: ellipse.center,
                radius: ellipse.radiusX,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false,
                stroke: ellipse.stroke
            ))
        }

        // For general ellipses, approximate with bezier
        return ellipseArcToBezier(ellipse, startAngle: startAngle, endAngle: endAngle)
    }

    /// Approximate an elliptic arc with cubic bezier segments.
    private static func ellipseArcToBezier(_ ellipse: EllipseShape, startAngle: CGFloat, endAngle: CGFloat) -> AnyShape? {
        var span = endAngle - startAngle
        if span <= 0 { span += 2 * .pi }
        guard span > eps else { return nil }

        // Each bezier segment covers at most π/2 for good accuracy
        let segCount = max(1, Int(ceil(span / (.pi / 2))))
        let segSpan = span / CGFloat(segCount)
        let k = (4.0 / 3.0) * tan(segSpan / 4.0)

        var points: [BezierPoint] = []
        for i in 0...segCount {
            let angle = startAngle + CGFloat(i) * segSpan
            let pt = CGPoint(
                x: ellipse.center.x + ellipse.radiusX * cos(angle),
                y: ellipse.center.y + ellipse.radiusY * sin(angle)
            )
            let tangent = CGPoint(
                x: -ellipse.radiusX * sin(angle),
                y: ellipse.radiusY * cos(angle)
            )
            points.append(BezierPoint(
                point: pt,
                controlIn: CGPoint(x: pt.x - tangent.x * k, y: pt.y - tangent.y * k),
                controlOut: CGPoint(x: pt.x + tangent.x * k, y: pt.y + tangent.y * k)
            ))
        }

        // Endpoints: unused handles should collapse to the anchor
        points[0].controlIn = points[0].point
        points[points.count - 1].controlOut = points[points.count - 1].point

        guard points.count >= 2 else { return nil }
        return .bezier(BezierShape(points: points, isClosed: false, stroke: ellipse.stroke))
    }

    // MARK: - Intersection Finding

    private static func findIntersectionTs(shape: AnyShape, against others: [AnyShape], isClosed: Bool) -> [CGFloat] {
        var results: [CGFloat] = []
        for other in others {
            guard other.id != shape.id else { continue }

            // Arc-Arc: use analytical solution for exact intersection
            if case .arc(let targetArc) = shape, case .arc(let otherArc) = other {
                let hits = Intersection.arcArcIntersection(arc1: targetArc, arc2: otherArc)
                for pt in hits {
                    let angle = atan2(pt.y - targetArc.center.y, pt.x - targetArc.center.x)
                    if let t = targetArc.parameterForAngle(angle) {
                        results.append(t)
                    }
                }
                continue
            }

            let otherSegments = toSegments(other)
            for (s1, s2) in otherSegments {
                let ts = intersectTargetWithSegment(target: shape, segStart: s1, segEnd: s2)
                results.append(contentsOf: ts)
            }
        }
        return deduplicateTs(results, isClosed: isClosed)
    }

    private static func intersectTargetWithSegment(target: AnyShape, segStart: CGPoint, segEnd: CGPoint) -> [CGFloat] {
        switch target {
        case .line(let line):
            return intersectLineWithSegment(line: line, segStart: segStart, segEnd: segEnd)
        case .arc(let arc):
            return intersectArcWithSegment(arc: arc, segStart: segStart, segEnd: segEnd)
        case .bezier(let bezier):
            return intersectBezierWithSegment(bezier: bezier, segStart: segStart, segEnd: segEnd)
        case .ellipse(let ellipse):
            return intersectEllipseWithSegment(ellipse: ellipse, segStart: segStart, segEnd: segEnd)
        default:
            return []
        }
    }

    private static func intersectLineWithSegment(line: LineShape, segStart: CGPoint, segEnd: CGPoint) -> [CGFloat] {
        guard let pt = Intersection.lineLineIntersection(
            a1: line.startPoint, a2: line.endPoint,
            b1: segStart, b2: segEnd
        ) else { return [] }
        return [projectPointOnLine(pt, lineStart: line.startPoint, lineEnd: line.endPoint)]
    }

    private static func intersectArcWithSegment(arc: ArcShape, segStart: CGPoint, segEnd: CGPoint) -> [CGFloat] {
        let circleHits = Intersection.lineCircleIntersection(
            lineStart: segStart, lineEnd: segEnd,
            center: arc.center, radius: arc.radius
        )
        return circleHits.compactMap { pt in
            let angle = atan2(pt.y - arc.center.y, pt.x - arc.center.x)
            return arc.parameterForAngle(angle)
        }
    }

    private static func intersectBezierWithSegment(bezier: BezierShape, segStart: CGPoint, segEnd: CGPoint) -> [CGFloat] {
        let targetSegs = toBezierSamples(bezier)
        let total = targetSegs.count
        guard total > 0 else { return [] }

        var results: [CGFloat] = []
        for (idx, (s1, s2)) in targetSegs.enumerated() {
            guard let pt = Intersection.lineLineIntersection(a1: s1, a2: s2, b1: segStart, b2: segEnd) else { continue }
            let localT = projectOntoSegment(pt, from: s1, to: s2)
            let globalT = (CGFloat(idx) + localT) / CGFloat(total)
            results.append(globalT)
        }
        return results
    }

    private static func intersectEllipseWithSegment(ellipse: EllipseShape, segStart: CGPoint, segEnd: CGPoint) -> [CGFloat] {
        // Use line-circle for circular ellipses (exact), otherwise polyline approximation
        if abs(ellipse.radiusX - ellipse.radiusY) < 0.001 {
            let hits = Intersection.lineCircleIntersection(
                lineStart: segStart, lineEnd: segEnd,
                center: ellipse.center, radius: ellipse.radiusX
            )
            return hits.compactMap { pt in
                let angle = atan2(pt.y - ellipse.center.y, pt.x - ellipse.center.x)
                var t = angle / (2 * .pi)
                if t < 0 { t += 1 }
                return t
            }
        }

        let n = sampleCount
        var results: [CGFloat] = []
        for i in 0..<n {
            let a1 = CGFloat(i) / CGFloat(n) * 2 * .pi
            let a2 = CGFloat(i + 1) / CGFloat(n) * 2 * .pi
            let p1 = CGPoint(x: ellipse.center.x + ellipse.radiusX * cos(a1), y: ellipse.center.y + ellipse.radiusY * sin(a1))
            let p2 = CGPoint(x: ellipse.center.x + ellipse.radiusX * cos(a2), y: ellipse.center.y + ellipse.radiusY * sin(a2))
            guard let pt = Intersection.lineLineIntersection(a1: p1, a2: p2, b1: segStart, b2: segEnd) else { continue }
            let localT = projectOntoSegment(pt, from: p1, to: p2)
            results.append((CGFloat(i) + localT) / CGFloat(n))
        }
        return results
    }

    // MARK: - Shape → Line Segments

    private static func toSegments(_ shape: AnyShape) -> [(CGPoint, CGPoint)] {
        switch shape {
        case .line(let l):
            return [(l.startPoint, l.endPoint)]

        case .rectangle(let r):
            let o = r.origin, s = r.size
            let tl = o
            let tr = CGPoint(x: o.x + s.width, y: o.y)
            let br = CGPoint(x: o.x + s.width, y: o.y + s.height)
            let bl = CGPoint(x: o.x, y: o.y + s.height)
            return [(tl, tr), (tr, br), (br, bl), (bl, tl)]

        case .ellipse(let e):
            let n = sampleCount
            return (0..<n).map { i in
                let a1 = CGFloat(i) / CGFloat(n) * 2 * .pi
                let a2 = CGFloat(i + 1) / CGFloat(n) * 2 * .pi
                return (
                    CGPoint(x: e.center.x + e.radiusX * cos(a1), y: e.center.y + e.radiusY * sin(a1)),
                    CGPoint(x: e.center.x + e.radiusX * cos(a2), y: e.center.y + e.radiusY * sin(a2))
                )
            }

        case .arc(let a):
            let n = sampleCount
            return (0..<n).map { i in
                let t1 = CGFloat(i) / CGFloat(n)
                let t2 = CGFloat(i + 1) / CGFloat(n)
                return (a.pointAtParameter(t1), a.pointAtParameter(t2))
            }

        case .bezier(let b):
            return toBezierSamples(b)

        case .group(let g):
            return g.children.flatMap { toSegments($0) }

        case .dot, .text:
            return []
        }
    }

    private static func toBezierSamples(_ b: BezierShape) -> [(CGPoint, CGPoint)] {
        guard b.points.count >= 2 else { return [] }
        let segCount = b.isClosed ? b.points.count : b.points.count - 1
        let perSeg = max(sampleCount / max(segCount, 1), 8)
        var segs: [(CGPoint, CGPoint)] = []
        for i in 0..<segCount {
            let j = (i + 1) % b.points.count
            let p0 = b.points[i].point, c1 = b.points[i].controlOut
            let c2 = b.points[j].controlIn, p3 = b.points[j].point
            for s in 0..<perSeg {
                let t1 = CGFloat(s) / CGFloat(perSeg)
                let t2 = CGFloat(s + 1) / CGFloat(perSeg)
                segs.append((
                    evalCubic(t: t1, p0: p0, p1: c1, p2: c2, p3: p3),
                    evalCubic(t: t2, p0: p0, p1: c1, p2: c2, p3: p3)
                ))
            }
        }
        return segs
    }

    // MARK: - Point Projection

    private static func projectPoint(_ point: CGPoint, onto shape: AnyShape) -> CGFloat? {
        switch shape {
        case .line(let line):
            return projectPointOnLine(point, lineStart: line.startPoint, lineEnd: line.endPoint)
        case .arc(let arc):
            let angle = atan2(point.y - arc.center.y, point.x - arc.center.x)
            return arc.parameterForAngle(angle)
        case .bezier(let bezier):
            return projectPointOnBezier(point, bezier: bezier)
        default:
            return nil
        }
    }

    private static func projectPointOnLine(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return 0 }
        return max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lenSq))
    }

    private static func projectPointOnBezier(_ point: CGPoint, bezier: BezierShape) -> CGFloat {
        let segments = toBezierSamples(bezier)
        guard !segments.isEmpty else { return 0 }

        var bestT: CGFloat = 0
        var bestDist = CGFloat.infinity

        for (idx, (s1, s2)) in segments.enumerated() {
            let localT = projectOntoSegment(point, from: s1, to: s2)
            let proj = lerp(s1, s2, localT)
            let dist = point.distance(to: proj)
            if dist < bestDist {
                bestDist = dist
                bestT = (CGFloat(idx) + localT) / CGFloat(segments.count)
            }
        }
        return bestT
    }

    private static func projectOntoSegment(_ point: CGPoint, from s1: CGPoint, to s2: CGPoint) -> CGFloat {
        let dx = s2.x - s1.x
        let dy = s2.y - s1.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return 0 }
        return max(0, min(1, ((point.x - s1.x) * dx + (point.y - s1.y) * dy) / lenSq))
    }

    // MARK: - Shape Splitting

    private static func extractRange(from shape: AnyShape, start: CGFloat, end: CGFloat) -> AnyShape? {
        guard end - start > eps else { return nil }

        switch shape {
        case .line(let line):
            return extractLineRange(line, start: start, end: end)
        case .arc(let arc):
            return extractArcRange(arc, start: start, end: end)
        case .bezier(let bezier):
            return extractBezierRange(bezier, start: start, end: end)
        default:
            return nil
        }
    }

    private static func extractLineRange(_ line: LineShape, start: CGFloat, end: CGFloat) -> AnyShape {
        let newStart = lerp(line.startPoint, line.endPoint, start)
        let newEnd = lerp(line.startPoint, line.endPoint, end)
        return .line(LineShape(start: newStart, end: newEnd, stroke: line.stroke))
    }

    private static func extractArcRange(_ arc: ArcShape, start: CGFloat, end: CGFloat) -> AnyShape {
        return .arc(ArcShape(
            center: arc.center,
            radius: arc.radius,
            startAngle: arc.angleAtParameter(start),
            endAngle: arc.angleAtParameter(end),
            clockwise: arc.clockwise,
            stroke: arc.stroke
        ))
    }

    private static func extractBezierRange(_ bezier: BezierShape, start: CGFloat, end: CGFloat) -> AnyShape? {
        guard bezier.points.count >= 2 else { return nil }

        var curve = bezier

        if start > eps {
            let (_, right) = splitBezierShape(curve, at: start)
            curve = right
            let adjustedEnd = (end - start) / (1.0 - start)
            if adjustedEnd < 1 - eps {
                let (left, _) = splitBezierShape(curve, at: min(adjustedEnd, 1))
                curve = left
            }
        } else if end < 1 - eps {
            let (left, _) = splitBezierShape(curve, at: end)
            curve = left
        }

        guard curve.points.count >= 2 else { return nil }
        return .bezier(curve)
    }

    /// Split a bezier shape at global parameter t using De Casteljau.
    private static func splitBezierShape(_ bezier: BezierShape, at globalT: CGFloat) -> (BezierShape, BezierShape) {
        let segCount = bezier.isClosed ? bezier.points.count : bezier.points.count - 1
        guard segCount > 0 else { return (bezier, bezier) }

        let scaled = globalT * CGFloat(segCount)
        let segIndex = min(Int(scaled), segCount - 1)
        let localT = max(0, min(1, scaled - CGFloat(segIndex)))

        let j = (segIndex + 1) % bezier.points.count
        let p0 = bezier.points[segIndex].point
        let c1 = bezier.points[segIndex].controlOut
        let c2 = bezier.points[j].controlIn
        let p3 = bezier.points[j].point

        let q0 = lerp(p0, c1, localT)
        let q1 = lerp(c1, c2, localT)
        let q2 = lerp(c2, p3, localT)
        let r0 = lerp(q0, q1, localT)
        let r1 = lerp(q1, q2, localT)
        let s  = lerp(r0, r1, localT)

        var leftPoints = Array(bezier.points[0...segIndex])
        leftPoints[leftPoints.count - 1].controlOut = q0
        leftPoints.append(BezierPoint(point: s, controlIn: r0, controlOut: s))

        var rightPoints: [BezierPoint] = [BezierPoint(point: s, controlIn: s, controlOut: r1)]
        if segIndex + 1 < bezier.points.count {
            var rest = Array(bezier.points[(segIndex + 1)...])
            rest[0].controlIn = q2
            rightPoints.append(contentsOf: rest)
        }

        return (
            BezierShape(points: leftPoints, isClosed: false, stroke: bezier.stroke),
            BezierShape(points: rightPoints, isClosed: false, stroke: bezier.stroke)
        )
    }

    // MARK: - Helpers

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func evalCubic(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let mt3 = mt2 * mt
        let t2 = t * t
        let t3 = t2 * t
        return CGPoint(
            x: mt3 * p0.x + 3 * mt2 * t * p1.x + 3 * mt * t2 * p2.x + t3 * p3.x,
            y: mt3 * p0.y + 3 * mt2 * t * p1.y + 3 * mt * t2 * p2.y + t3 * p3.y
        )
    }

    private static func distanceToSegment(_ point: CGPoint, _ s1: CGPoint, _ s2: CGPoint) -> CGFloat {
        let t = projectOntoSegment(point, from: s1, to: s2)
        let proj = lerp(s1, s2, t)
        return point.distance(to: proj)
    }

    private static func deduplicateTs(_ ts: [CGFloat], isClosed: Bool) -> [CGFloat] {
        let filtered: [CGFloat]
        if isClosed {
            filtered = ts.filter { $0 >= 0 && $0 < 1 }.sorted()
        } else {
            filtered = ts.filter { $0 > eps && $0 < 1 - eps }.sorted()
        }
        var result: [CGFloat] = []
        for t in filtered {
            if let last = result.last, abs(t - last) < 0.005 { continue }
            result.append(t)
        }
        // For closed curves, check wrap-around duplicate
        if isClosed, result.count >= 2 {
            if let first = result.first, let last = result.last, (1.0 - last + first) < 0.005 {
                result.removeLast()
            }
        }
        return result
    }
}
