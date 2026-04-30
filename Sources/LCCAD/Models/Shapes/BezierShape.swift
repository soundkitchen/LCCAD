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

    private func distanceToCubicBezier(point: CGPoint, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, steps: Int = 20) -> CGFloat {
        var minDist = CGFloat.infinity
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let bezierPoint = cubicBezierPoint(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
            let dist = point.distance(to: bezierPoint)
            minDist = min(minDist, dist)
        }
        return minDist
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
