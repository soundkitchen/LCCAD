import Foundation
import CoreGraphics

/// Arc-length lookup table for curves whose arc length has no closed form
/// (cubic bezier segments, general ellipses).
///
/// Built by sampling the curve at uniform parameter steps and accumulating
/// chord lengths. Queries map an arc-length distance back to the curve's
/// native parameter via binary search plus linear interpolation between the
/// bracketing samples.
///
/// Shared by `BezierSegmentPathWalker` and `EllipsePathWalker` so both use
/// identical sampling/interpolation behavior — a precision or performance fix
/// applied here reaches every walker at once.
struct ArcLengthTable {
    private let entries: [(parameter: CGFloat, arcLength: CGFloat)]

    /// Samples `point` at `sampleCount` uniform parameter steps over
    /// `[0, maxParameter]` and accumulates chord lengths.
    /// `sampleCount` must be at least 1.
    init(sampleCount: Int, maxParameter: CGFloat = 1, point: (CGFloat) -> CGPoint) {
        precondition(sampleCount >= 1, "ArcLengthTable requires at least one sample")
        var table: [(parameter: CGFloat, arcLength: CGFloat)] = [(0, 0)]
        var prevPoint = point(0)
        var accumLen: CGFloat = 0
        for i in 1...sampleCount {
            let parameter = maxParameter * CGFloat(i) / CGFloat(sampleCount)
            let pt = point(parameter)
            accumLen += prevPoint.distance(to: pt)
            table.append((parameter, accumLen))
            prevPoint = pt
        }
        self.entries = table
    }

    /// Total arc length of the sampled curve (chord-length approximation).
    var totalLength: CGFloat {
        entries.last?.arcLength ?? 0
    }

    /// Curve parameter at the given arc-length distance. Distances outside
    /// `[0, totalLength]` are clamped.
    func parameter(atDistance distance: CGFloat) -> CGFloat {
        let target = min(max(distance, 0), totalLength)
        // Lower-bound binary search: first entry with arcLength >= target.
        var lo = 0
        var hi = entries.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].arcLength < target { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return entries[0].parameter }
        let a = entries[lo - 1]
        let b = entries[lo]
        let span = b.arcLength - a.arcLength
        let t = span > 0 ? (target - a.arcLength) / span : 0
        return a.parameter + (b.parameter - a.parameter) * t
    }
}
