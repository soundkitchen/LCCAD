import Foundation
import CoreGraphics

// MARK: - PathWalkable Protocol

protocol PathWalkable {
    var pathLength: CGFloat { get }
    func pointAtDistance(_ distance: CGFloat) -> CGPoint
    func tangentAtDistance(_ distance: CGFloat) -> CGFloat // radians
    /// True when the path forms a closed loop (start point coincides with end point),
    /// e.g. a rectangle, ellipse, closed bezier, or a welded outline. The stitch engine
    /// uses this to avoid placing a duplicate hole at the seam and to distribute holes
    /// evenly around the loop.
    var isClosed: Bool { get }
    /// Arc-length positions of sharp corners (direction discontinuities) along the path.
    /// The stitch engine anchors a hole on each corner so corners are never skipped.
    /// Smooth paths (line, arc, ellipse, smooth curve) report none.
    var cornerDistances: [CGFloat] { get }
}

extension PathWalkable {
    /// Most walkers describe an open segment; closed walkers override this.
    var isClosed: Bool { false }
    /// Most walkers are smooth; only composites expose interior corners.
    var cornerDistances: [CGFloat] { [] }
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
    let isClosed: Bool
    let cornerDistances: [CGFloat]
    private let cumulativeLengths: [CGFloat]

    /// Minimum tangent change at a joint for it to count as a corner. Tangentially
    /// joined segments (line→arc, smooth curves) fall below this; real vertices exceed it.
    private static let cornerThreshold: CGFloat = 5 * .pi / 180  // 5°

    init(segments: [PathWalkable], isClosed: Bool = false) {
        self.segments = segments
        self.isClosed = isClosed
        var cumulative: [CGFloat] = [0]
        for seg in segments {
            cumulative.append(cumulative.last! + seg.pathLength)
        }
        self.cumulativeLengths = cumulative
        self.cornerDistances = Self.detectCorners(segments: segments, cumulative: cumulative, isClosed: isClosed)
    }

    /// Find joints whose incoming and outgoing tangents differ sharply. For a closed
    /// path the seam (last segment → first segment) is also checked, reported at 0.
    private static func detectCorners(segments: [PathWalkable], cumulative: [CGFloat], isClosed: Bool) -> [CGFloat] {
        guard segments.count >= 2 else { return [] }
        var corners: [CGFloat] = []
        for i in 0..<(segments.count - 1) {
            let incoming = segments[i].tangentAtDistance(segments[i].pathLength)
            let outgoing = segments[i + 1].tangentAtDistance(0)
            if angularDifference(incoming, outgoing) > cornerThreshold {
                corners.append(cumulative[i + 1])
            }
        }
        if isClosed {
            let incoming = segments[segments.count - 1].tangentAtDistance(segments[segments.count - 1].pathLength)
            let outgoing = segments[0].tangentAtDistance(0)
            if angularDifference(incoming, outgoing) > cornerThreshold {
                corners.append(0)
            }
        }
        return corners
    }

    /// Smallest absolute angle between two directions, in [0, π].
    private static func angularDifference(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        abs(atan2(sin(a - b), cos(a - b)))
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

// MARK: - Ellipse Path Walker (full ellipse / circle)

/// Walks a full ellipse (or circle when radiusX == radiusY). For a circle the arc
/// length is linear in the parametric angle, but for a general ellipse it is not, so
/// an arc-length lookup table is built (mirroring `BezierSegmentPathWalker`). The
/// ellipse's `rotation` is applied around its center.
struct EllipsePathWalker: PathWalkable {
    let center: CGPoint
    let radiusX: CGFloat
    let radiusY: CGFloat
    let rotation: CGFloat

    private let sampleCount = 180
    private let lut: [(theta: CGFloat, arcLen: CGFloat)]

    init(ellipse: EllipseShape) {
        self.center = ellipse.center
        self.radiusX = ellipse.radiusX
        self.radiusY = ellipse.radiusY
        self.rotation = ellipse.rotation

        var table: [(theta: CGFloat, arcLen: CGFloat)] = [(0, 0)]
        var prevPoint = Self.point(theta: 0, center: center, radiusX: radiusX, radiusY: radiusY, rotation: rotation)
        var accumLen: CGFloat = 0
        for i in 1...sampleCount {
            let theta = 2 * .pi * CGFloat(i) / CGFloat(sampleCount)
            let pt = Self.point(theta: theta, center: center, radiusX: radiusX, radiusY: radiusY, rotation: rotation)
            accumLen += prevPoint.distance(to: pt)
            table.append((theta, accumLen))
            prevPoint = pt
        }
        self.lut = table
    }

    var isClosed: Bool { true }

    var pathLength: CGFloat {
        lut.last?.arcLen ?? 0
    }

    func pointAtDistance(_ distance: CGFloat) -> CGPoint {
        Self.point(theta: thetaForDistance(distance), center: center, radiusX: radiusX, radiusY: radiusY, rotation: rotation)
    }

    func tangentAtDistance(_ distance: CGFloat) -> CGFloat {
        // Numerical tangent: robust against rotation-direction sign mistakes and
        // accurate enough for hole orientation.
        let len = pathLength
        guard len > 0 else { return 0 }
        let delta = max(len * 1e-4, 1e-4)
        let d0 = min(max(distance - delta, 0), len)
        let d1 = min(max(distance + delta, 0), len)
        let p0 = pointAtDistance(d0)
        let p1 = pointAtDistance(d1)
        return atan2(p1.y - p0.y, p1.x - p0.x)
    }

    private static func point(theta: CGFloat, center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, rotation: CGFloat) -> CGPoint {
        let local = CGPoint(x: center.x + radiusX * cos(theta), y: center.y + radiusY * sin(theta))
        return rotation == 0 ? local : local.rotated(around: center, angle: rotation)
    }

    private func thetaForDistance(_ distance: CGFloat) -> CGFloat {
        let len = pathLength
        guard len > 0 else { return 0 }
        let target = min(max(distance, 0), len)
        // Binary search the LUT for the bracketing samples, then interpolate theta.
        var lo = 0
        var hi = lut.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if lut[mid].arcLen < target { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return lut[0].theta }
        let a = lut[lo - 1]
        let b = lut[lo]
        let span = b.arcLen - a.arcLen
        let t = span > 0 ? (target - a.arcLen) / span : 0
        return a.theta + (b.theta - a.theta) * t
    }
}

// MARK: - Reversed Path Walker

/// Walks any path in the opposite direction. Used when welding outline segments
/// so they connect head-to-tail regardless of their drawn orientation.
struct ReversedPathWalker: PathWalkable {
    let inner: PathWalkable

    var pathLength: CGFloat { inner.pathLength }
    var isClosed: Bool { inner.isClosed }

    func pointAtDistance(_ distance: CGFloat) -> CGPoint {
        inner.pointAtDistance(inner.pathLength - distance)
    }

    func tangentAtDistance(_ distance: CGFloat) -> CGFloat {
        inner.tangentAtDistance(inner.pathLength - distance) + .pi
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
            if segments.count == 1 { return segments[0] }
            return CompositePathWalker(segments: segments, isClosed: bezier.isClosed)

        case .rectangle(let rect):
            let corners = rect.rotatedCorners  // [TL, TR, BR, BL] after rotation
            let segments: [PathWalkable] = [
                LinePathWalker(start: corners[0], end: corners[1]),
                LinePathWalker(start: corners[1], end: corners[2]),
                LinePathWalker(start: corners[2], end: corners[3]),
                LinePathWalker(start: corners[3], end: corners[0]),
            ]
            return CompositePathWalker(segments: segments, isClosed: true)

        case .ellipse(let ellipse):
            return EllipsePathWalker(ellipse: ellipse)

        default:
            return nil  // text, dot, dimension lines not stitchable
        }
    }
}
