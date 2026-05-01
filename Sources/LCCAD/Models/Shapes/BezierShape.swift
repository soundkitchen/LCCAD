import Foundation
import CoreGraphics

struct BezierPoint: Codable, Equatable, Sendable {
    var point: CGPoint
    var controlIn: CGPoint   // control handle towards previous point
    var controlOut: CGPoint  // control handle towards next point
}

struct BezierShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var points: [BezierPoint]
    var isClosed: Bool
    var stroke: StrokeStyle
    var isLocked: Bool = false

    init(id: UUID = UUID(), points: [BezierPoint], isClosed: Bool = false, stroke: StrokeStyle = .default) {
        self.id = id
        self.points = points
        self.isClosed = isClosed
        self.stroke = stroke
    }

    var boundingBox: CGRect {
        guard !points.isEmpty else { return .zero }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for bp in points {
            for p in [bp.point, bp.controlIn, bp.controlOut] {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Tight bbox around the rendered curve. Samples each segment to avoid the
    /// overshoot that handle-inclusive `boundingBox` introduces — used to place
    /// mirror copies flush against the visible edge.
    var visualBoundingBox: CGRect {
        guard points.count >= 2 else {
            if let p = points.first?.point {
                return CGRect(x: p.x, y: p.y, width: 0, height: 0)
            }
            return .zero
        }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        let segmentCount = isClosed ? points.count : points.count - 1
        let steps = 32
        for i in 0..<segmentCount {
            let j = (i + 1) % points.count
            let p0 = points[i].point
            let p1 = points[i].controlOut
            let p2 = points[j].controlIn
            let p3 = points[j].point
            for k in 0...steps {
                let t = CGFloat(k) / CGFloat(steps)
                let p = cubicBezierPoint(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        guard points.count >= 2 else { return false }

        let segmentCount = isClosed ? points.count : points.count - 1
        for i in 0..<segmentCount {
            let j = (i + 1) % points.count
            let p0 = points[i].point
            let p1 = points[i].controlOut
            let p2 = points[j].controlIn
            let p3 = points[j].point

            if distanceToCubicBezier(point: point, p0: p0, p1: p1, p2: p2, p3: p3) <= tolerance {
                return true
            }
        }
        return false
    }

    mutating func translate(by delta: CGPoint) {
        for i in points.indices {
            points[i].point = points[i].point + delta
            points[i].controlIn = points[i].controlIn + delta
            points[i].controlOut = points[i].controlOut + delta
        }
    }

    mutating func mirror(axis: MirrorAxis) {
        // Reflect every control point in place. Keeping the point order intact
        // produces the correct geometric mirror — swapping in/out would distort
        // the curve because the segment topology stays the same.
        points = points.map { bp in
            BezierPoint(
                point: bp.point.mirrored(across: axis),
                controlIn: bp.controlIn.mirrored(across: axis),
                controlOut: bp.controlOut.mirrored(across: axis)
            )
        }
    }

    mutating func rotate(around center: CGPoint, angle: CGFloat) {
        points = points.map { bp in
            BezierPoint(
                point: bp.point.rotated(around: center, angle: angle),
                controlIn: bp.controlIn.rotated(around: center, angle: angle),
                controlOut: bp.controlOut.rotated(around: center, angle: angle)
            )
        }
    }

    private func distanceToCubicBezier(point: CGPoint, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, steps: Int = 24) -> CGFloat {
        // Sample the curve and measure distance to the polyline between samples,
        // not to the discrete sample points. Point-to-point sampling underestimates
        // proximity for clicks that fall between samples — the gap between samples
        // on screen can easily exceed the click tolerance.
        var minDist = CGFloat.infinity
        var prev = cubicBezierPoint(t: 0, p0: p0, p1: p1, p2: p2, p3: p3)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let cur = cubicBezierPoint(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
            let dist = distanceFromPointToSegment(point: point, start: prev, end: cur)
            minDist = min(minDist, dist)
            prev = cur
        }
        return minDist
    }

    private func distanceFromPointToSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSq = dx * dx + dy * dy
        if lengthSq == 0 { return point.distance(to: start) }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSq
        t = max(0, min(1, t))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return point.distance(to: projection)
    }

    private func cubicBezierPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
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
}
