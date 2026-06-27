import Foundation
import CoreGraphics

/// A single cubic Bézier segment. Used as the common representation for
/// curve×curve intersection: Bézier segments, circular arcs, and ellipses are
/// all reduced to cubic segments so one robust intersection routine serves all.
struct CubicSegment {
    var p0: CGPoint
    var c1: CGPoint
    var c2: CGPoint
    var p3: CGPoint

    /// Axis-aligned bounds of the 4 control points (a superset of the curve).
    var controlBounds: CGRect {
        let minX = min(min(p0.x, c1.x), min(c2.x, p3.x))
        let minY = min(min(p0.y, c1.y), min(c2.y, p3.y))
        let maxX = max(max(p0.x, c1.x), max(c2.x, p3.x))
        let maxY = max(max(p0.y, c1.y), max(c2.y, p3.y))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func point(at t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p3.y
        )
    }

    /// De Casteljau split at t = 0.5 → (left half, right half).
    func split05() -> (CubicSegment, CubicSegment) {
        let m01 = CubicSegment.mid(p0, c1)
        let m12 = CubicSegment.mid(c1, c2)
        let m23 = CubicSegment.mid(c2, p3)
        let m012 = CubicSegment.mid(m01, m12)
        let m123 = CubicSegment.mid(m12, m23)
        let m = CubicSegment.mid(m012, m123)
        return (
            CubicSegment(p0: p0, c1: m01, c2: m012, p3: m),
            CubicSegment(p0: m, c1: m123, c2: m23, p3: p3)
        )
    }

    private static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }
}

extension Intersection {
    /// True intersections of two cubic Bézier segments via recursive bounding-box
    /// subdivision (no fixed-resolution polyline sampling). Returns, for each
    /// crossing, the parameter on each segment plus the intersection point.
    ///
    /// At every step the segment with the larger control-box is split, so the
    /// recursion converges in ~O(log(1/tolerance)) per intersection rather than
    /// the 4-way blow-up of splitting both.
    static func cubicCubicIntersections(
        _ a: CubicSegment, _ b: CubicSegment,
        tolerance: CGFloat = 1e-4, maxDepth: Int = 32
    ) -> [(ta: CGFloat, tb: CGFloat, point: CGPoint)] {
        var out: [(ta: CGFloat, tb: CGFloat, point: CGPoint)] = []

        func recurse(_ a: CubicSegment, _ ta0: CGFloat, _ ta1: CGFloat,
                     _ b: CubicSegment, _ tb0: CGFloat, _ tb1: CGFloat,
                     _ depth: Int) {
            let ba = a.controlBounds.insetBy(dx: -tolerance, dy: -tolerance)
            let bb = b.controlBounds
            guard ba.intersects(bb) else { return }

            let sizeA = max(a.controlBounds.width, a.controlBounds.height)
            let sizeB = max(b.controlBounds.width, b.controlBounds.height)

            if depth <= 0 || (sizeA <= tolerance && sizeB <= tolerance) {
                // Both curves are now near-linear over their sub-interval; solve
                // the chord-chord intersection and map the local params back to
                // the original [0,1] ranges.
                if let hit = segmentSegmentParametric(a.p0, a.p3, b.p0, b.p3) {
                    out.append((
                        ta0 + (ta1 - ta0) * hit.t,
                        tb0 + (tb1 - tb0) * hit.u,
                        hit.point
                    ))
                }
                return
            }

            if sizeA >= sizeB {
                let (a1, a2) = a.split05()
                let tm = (ta0 + ta1) * 0.5
                recurse(a1, ta0, tm, b, tb0, tb1, depth - 1)
                recurse(a2, tm, ta1, b, tb0, tb1, depth - 1)
            } else {
                let (b1, b2) = b.split05()
                let tm = (tb0 + tb1) * 0.5
                recurse(a, ta0, ta1, b1, tb0, tm, depth - 1)
                recurse(a, ta0, ta1, b2, tm, tb1, depth - 1)
            }
        }

        recurse(a, 0, 1, b, 0, 1, maxDepth)
        return dedupeHits(out, minDistance: max(tolerance * 4, 1e-3))
    }

    /// Segment-segment intersection that also reports the parametric position
    /// (t along a, u along b), both clamped to [0, 1].
    private static func segmentSegmentParametric(
        _ a1: CGPoint, _ a2: CGPoint, _ b1: CGPoint, _ b2: CGPoint
    ) -> (point: CGPoint, t: CGFloat, u: CGFloat)? {
        let d1x = a2.x - a1.x, d1y = a2.y - a1.y
        let d2x = b2.x - b1.x, d2y = b2.y - b1.y
        let cross = d1x * d2y - d1y * d2x
        guard abs(cross) > 1e-12 else { return nil } // parallel / degenerate
        let dx = b1.x - a1.x, dy = b1.y - a1.y
        let t = (dx * d2y - dy * d2x) / cross
        let u = (dx * d1y - dy * d1x) / cross
        guard t >= -1e-6, t <= 1 + 1e-6, u >= -1e-6, u <= 1 + 1e-6 else { return nil }
        let tc = max(0, min(1, t))
        return (CGPoint(x: a1.x + tc * d1x, y: a1.y + tc * d1y),
                tc, max(0, min(1, u)))
    }

    private static func dedupeHits(
        _ hits: [(ta: CGFloat, tb: CGFloat, point: CGPoint)],
        minDistance: CGFloat
    ) -> [(ta: CGFloat, tb: CGFloat, point: CGPoint)] {
        var result: [(ta: CGFloat, tb: CGFloat, point: CGPoint)] = []
        for hit in hits {
            if result.contains(where: { $0.point.distance(to: hit.point) < minDistance }) { continue }
            result.append(hit)
        }
        return result
    }

    // MARK: - Shape → Cubic segment conversion

    /// Cubic segments tracing a (possibly elliptical) arc. Works for circles
    /// (rx == ry) and ellipses alike; `signedSpan` is positive CCW, negative CW.
    /// Each output segment spans at most 90° for tight accuracy (~1e-4·r error).
    static func arcCubics(
        center: CGPoint, rx: CGFloat, ry: CGFloat,
        startAngle: CGFloat, signedSpan: CGFloat
    ) -> [CubicSegment] {
        let absSpan = abs(signedSpan)
        guard absSpan > 1e-9, rx > 0, ry > 0 else { return [] }

        let count = max(1, Int(ceil(absSpan / (.pi / 2))))
        let seg = signedSpan / CGFloat(count)
        let k = (4.0 / 3.0) * tan(seg / 4.0)

        func pt(_ a: CGFloat) -> CGPoint {
            CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a))
        }
        func tangent(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a), y: ry * cos(a))
        }

        var segments: [CubicSegment] = []
        for i in 0..<count {
            let a0 = startAngle + CGFloat(i) * seg
            let a1 = a0 + seg
            let p0 = pt(a0), p3 = pt(a1)
            let t0 = tangent(a0), t1 = tangent(a1)
            segments.append(CubicSegment(
                p0: p0,
                c1: CGPoint(x: p0.x + k * t0.x, y: p0.y + k * t0.y),
                c2: CGPoint(x: p3.x - k * t1.x, y: p3.y - k * t1.y),
                p3: p3
            ))
        }
        return segments
    }

    /// Cubic segments of a poly-Bézier shape, one per Bézier span. The index of
    /// each segment matches the shape's span index, so a caller can recover the
    /// global parameter as `(index + localT) / count`.
    static func bezierCubics(_ bezier: BezierShape) -> [CubicSegment] {
        guard bezier.points.count >= 2 else { return [] }
        let spanCount = bezier.isClosed ? bezier.points.count : bezier.points.count - 1
        var segments: [CubicSegment] = []
        for i in 0..<spanCount {
            let j = (i + 1) % bezier.points.count
            segments.append(CubicSegment(
                p0: bezier.points[i].point,
                c1: bezier.points[i].controlOut,
                c2: bezier.points[j].controlIn,
                p3: bezier.points[j].point
            ))
        }
        return segments
    }
}
