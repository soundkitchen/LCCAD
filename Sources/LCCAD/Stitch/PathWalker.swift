import Foundation
import CoreGraphics

// MARK: - PathWalkable Protocol

protocol PathWalkable {
    var pathLength: CGFloat { get }
    func pointAtDistance(_ distance: CGFloat) -> CGPoint
    func tangentAtDistance(_ distance: CGFloat) -> CGFloat // radians
}

// MARK: - Line Path Walker

struct LinePathWalker: PathWalkable {
    let start: CGPoint
    let end: CGPoint

    var pathLength: CGFloat {
        start.distance(to: end)
    }

    func pointAtDistance(_ distance: CGFloat) -> CGPoint {
        let len = pathLength
        guard len > 0 else { return start }
        let t = min(max(distance / len, 0), 1)
        return CGPoint(
            x: start.x + (end.x - start.x) * t,
            y: start.y + (end.y - start.y) * t
        )
    }

    func tangentAtDistance(_ distance: CGFloat) -> CGFloat {
        atan2(end.y - start.y, end.x - start.x)
    }
}

// MARK: - Arc Path Walker

struct ArcPathWalker: PathWalkable {
    let center: CGPoint
    let radius: CGFloat
    let startAngle: CGFloat
    let sweepAngle: CGFloat // positive = CCW, negative = CW

    init(arc: ArcShape) {
        self.center = arc.center
        self.radius = arc.radius
        self.startAngle = arc.startAngle

        // Compute sweep angle
        var sweep = arc.endAngle - arc.startAngle
        if arc.clockwise {
            // CW: sweep should be negative
            if sweep > 0 { sweep -= 2 * .pi }
            if sweep == 0 { sweep = -2 * .pi }
        } else {
            // CCW: sweep should be positive
            if sweep < 0 { sweep += 2 * .pi }
            if sweep == 0 { sweep = 2 * .pi }
        }
        self.sweepAngle = sweep
    }

    var pathLength: CGFloat {
        radius * abs(sweepAngle)
    }

    func pointAtDistance(_ distance: CGFloat) -> CGPoint {
        let len = pathLength
        guard len > 0 else { return CGPoint(x: center.x + radius * cos(startAngle), y: center.y + radius * sin(startAngle)) }
        let t = min(max(distance / len, 0), 1)
        let angle = startAngle + sweepAngle * t
        return CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }

    func tangentAtDistance(_ distance: CGFloat) -> CGFloat {
        let len = pathLength
        guard len > 0 else { return startAngle + .pi / 2 }
        let t = min(max(distance / len, 0), 1)
        let angle = startAngle + sweepAngle * t
        // Tangent is perpendicular to radius; direction depends on sweep sign
        if sweepAngle >= 0 {
            return angle + .pi / 2  // CCW: tangent is 90° ahead
        } else {
            return angle - .pi / 2  // CW: tangent is 90° behind
        }
    }
}

// MARK: - Bezier Segment Path Walker (single cubic segment)

struct BezierSegmentPathWalker: PathWalkable {
    let p0: CGPoint
    let p1: CGPoint  // control out of p0
    let p2: CGPoint  // control in of p3
    let p3: CGPoint

    private let sampleCount = 100
    private let lut: [(t: CGFloat, arcLen: CGFloat)]

    init(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3

        // Build arc-length lookup table
        var table: [(t: CGFloat, arcLen: CGFloat)] = [(0, 0)]
        var prevPoint = p0
        var accumLen: CGFloat = 0
        for i in 1...sampleCount {
            let t = CGFloat(i) / CGFloat(sampleCount)
            let pt = Self.evalCubic(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
            accumLen += prevPoint.distance(to: pt)
            table.append((t, accumLen))
            prevPoint = pt
        }
        self.lut = table
    }

    var pathLength: CGFloat {
        lut.last?.arcLen ?? 0
    }

    func pointAtDistance(_ distance: CGFloat) -> CGPoint {
        let t = tForDistance(distance)
        return Self.evalCubic(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
    }

    func tangentAtDistance(_ distance: CGFloat) -> CGFloat {
        let t = tForDistance(distance)
        let d = Self.evalCubicDerivative(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
        return atan2(d.y, d.x)
    }

    private func tForDistance(_ distance: CGFloat) -> CGFloat {
        let d = min(max(distance, 0), pathLength)
        // Binary search in LUT
        var lo = 0, hi = lut.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if lut[mid].arcLen <= d {
                lo = mid
            } else {
                hi = mid
            }
        }
        let loEntry = lut[lo]
        let hiEntry = lut[hi]
        let segLen = hiEntry.arcLen - loEntry.arcLen
        if segLen < 1e-10 { return loEntry.t }
        let frac = (d - loEntry.arcLen) / segLen
        return loEntry.t + (hiEntry.t - loEntry.t) * frac
    }

    static func evalCubic(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
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

    static func evalCubicDerivative(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let t2 = t * t
        return CGPoint(
            x: 3 * mt2 * (p1.x - p0.x) + 6 * mt * t * (p2.x - p1.x) + 3 * t2 * (p3.x - p2.x),
            y: 3 * mt2 * (p1.y - p0.y) + 6 * mt * t * (p2.y - p1.y) + 3 * t2 * (p3.y - p2.y)
        )
    }
}

// MARK: - Composite Path Walker (chains multiple segments)

struct CompositePathWalker: PathWalkable {
    let segments: [PathWalkable]
    private let cumulativeLengths: [CGFloat]

    init(segments: [PathWalkable]) {
        self.segments = segments
        var cumulative: [CGFloat] = [0]
        for seg in segments {
            cumulative.append(cumulative.last! + seg.pathLength)
        }
        self.cumulativeLengths = cumulative
    }

    var pathLength: CGFloat {
        cumulativeLengths.last ?? 0
    }

    func pointAtDistance(_ distance: CGFloat) -> CGPoint {
        let (segIdx, localDist) = findSegment(distance)
        return segments[segIdx].pointAtDistance(localDist)
    }

    func tangentAtDistance(_ distance: CGFloat) -> CGFloat {
        let (segIdx, localDist) = findSegment(distance)
        return segments[segIdx].tangentAtDistance(localDist)
    }

    private func findSegment(_ distance: CGFloat) -> (Int, CGFloat) {
        let d = min(max(distance, 0), pathLength)
        for i in 0..<segments.count {
            if d <= cumulativeLengths[i + 1] || i == segments.count - 1 {
                let localDist = d - cumulativeLengths[i]
                return (i, localDist)
            }
        }
        return (0, 0)
    }
}

// MARK: - Factory

enum PathWalkerFactory {
    static func walker(for shape: AnyShape) -> PathWalkable? {
        switch shape {
        case .line(let line):
            return LinePathWalker(start: line.startPoint, end: line.endPoint)

        case .arc(let arc):
            return ArcPathWalker(arc: arc)

        case .bezier(let bezier):
            guard bezier.points.count >= 2 else { return nil }
            let segCount = bezier.isClosed ? bezier.points.count : bezier.points.count - 1
            var segments: [PathWalkable] = []
            for i in 0..<segCount {
                let j = (i + 1) % bezier.points.count
                segments.append(BezierSegmentPathWalker(
                    p0: bezier.points[i].point,
                    p1: bezier.points[i].controlOut,
                    p2: bezier.points[j].controlIn,
                    p3: bezier.points[j].point
                ))
            }
            return segments.count == 1 ? segments[0] : CompositePathWalker(segments: segments)

        case .rectangle(let rect):
            let o = rect.origin
            let s = rect.size
            let tl = o
            let tr = CGPoint(x: o.x + s.width, y: o.y)
            let br = CGPoint(x: o.x + s.width, y: o.y + s.height)
            let bl = CGPoint(x: o.x, y: o.y + s.height)
            let segments: [PathWalkable] = [
                LinePathWalker(start: tl, end: tr),
                LinePathWalker(start: tr, end: br),
                LinePathWalker(start: br, end: bl),
                LinePathWalker(start: bl, end: tl),
            ]
            return CompositePathWalker(segments: segments)

        default:
            return nil  // text, dot, ellipse not stitchable
        }
    }
}
