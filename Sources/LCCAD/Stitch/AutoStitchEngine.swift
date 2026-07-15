import Foundation
import CoreGraphics

enum AutoStitchEngine {
    /// Generate stitch holes along a walkable path using the given pricking iron.
    ///
    /// Placement aims for tidy spacing on *any* shape:
    /// - Paths with sharp corners (rectangle, welded outline, pocket): a hole is anchored
    ///   on every corner and each corner-to-corner span is filled with evenly spaced holes
    ///   (~pitch). Even spacing avoids the cluster you'd get from marching a fixed pitch
    ///   into a corner whose span isn't a whole multiple of the pitch.
    /// - Cornered paths with `Even Count`: exactly `holeCount` holes total (clamped up to
    ///   the anchor count so every corner keeps its hole); the remaining holes go to the
    ///   span with the widest current interval, one at a time, minimizing the largest gap.
    /// - Closed smooth paths (circle, ellipse, smooth blob): holes are spread evenly around
    ///   the loop with no seam duplicate.
    /// - Open smooth paths (a single line or open curve): `Fixed` keeps an exact pitch from
    ///   the start; `Variable` evens the spacing so holes land on both ends; `Even Count`
    ///   places exactly `holeCount` holes (both ends included), ignoring the pitch.
    /// - Closed smooth paths also honor `Even Count` (exactly `holeCount` holes around the
    ///   loop). Exact counts on any path are the foundation for matching hole counts
    ///   across parts (駒合わせ).
    static func generateHoles(
        along walker: PathWalkable,
        iron: PrickingIron,
        mode: StitchMode = .fixedPitch,
        holeCount: Int? = nil
    ) -> [StitchHole] {
        let total = walker.pathLength
        guard total > 0, iron.pitch > 0 else { return [] }

        let corners = normalizedCorners(walker.cornerDistances, total: total)
        if !corners.isEmpty {
            if mode == .evenCount, let count = holeCount {
                return cornerConstrainedEvenCountHoles(
                    along: walker, total: total, count: count, holeAngle: iron.holeAngle, corners: corners
                )
            }
            return cornerAnchoredHoles(
                along: walker, total: total, pitch: iron.pitch, holeAngle: iron.holeAngle, corners: corners
            )
        }

        // No corners: a smooth path. Even Count applies to open and closed runs alike;
        // without a count it degrades to Variable (evened spacing at ~pitch).
        if mode == .evenCount, let count = holeCount {
            return evenCountHoles(along: walker, count: count, holeAngle: iron.holeAngle)
        }

        // Closed loops are always evened (a fixed march would cluster at the seam);
        // open runs honor the selected mode.
        if walker.isClosed {
            return variablePitchHoles(along: walker, targetPitch: iron.pitch, holeAngle: iron.holeAngle)
        }
        switch mode {
        case .fixedPitch:
            return fixedPitchHoles(along: walker, pitch: iron.pitch, holeAngle: iron.holeAngle)
        case .variablePitch, .evenCount:
            return variablePitchHoles(along: walker, targetPitch: iron.pitch, holeAngle: iron.holeAngle)
        }
    }

    // MARK: - Count estimators (for matching hole counts across parts)

    /// Hole count the default pitch-driven placement produces. Counting by generating
    /// keeps the estimate from ever drifting out of sync with actual placement.
    /// `.variablePitch` is the canonical estimate: cornered paths ignore the mode and
    /// closed smooth paths are always evened, so this predicts an even layout at ~pitch.
    static func naturalHoleCount(along walker: PathWalkable, iron: PrickingIron) -> Int {
        generateHoles(along: walker, iron: iron, mode: .variablePitch).count
    }

    /// Corner count after normalization (wrap, sort, near-duplicate removal) — the
    /// corners placement actually anchors. Raw `cornerDistances` may hold duplicates
    /// on welded paths, so displays should use this rather than the raw count.
    static func normalizedCornerCount(along walker: PathWalkable) -> Int {
        let total = walker.pathLength
        guard total > 0 else { return 0 }
        return normalizedCorners(walker.cornerDistances, total: total).count
    }

    /// Smallest `holeCount` the engine honors without clamping: every corner anchor
    /// (plus both endpoints on an open path) always keeps its hole.
    static func minimumHoleCount(along walker: PathWalkable) -> Int {
        let total = walker.pathLength
        guard total > 0 else { return 0 }
        let corners = normalizedCorners(walker.cornerDistances, total: total)
        if corners.isEmpty { return walker.isClosed ? 1 : 2 }
        if walker.isClosed { return corners.count }
        let interior = corners.filter { $0 > 1e-6 && $0 < total - 1e-6 }
        return interior.count + 2
    }

    // MARK: - Corner-anchored placement (even spacing per span)

    /// Wrap corner distances into [0, total), sort, and drop near-duplicates.
    private static func normalizedCorners(_ raw: [CGFloat], total: CGFloat) -> [CGFloat] {
        let wrapped = raw
            .map { d -> CGFloat in
                var m = d.truncatingRemainder(dividingBy: total)
                if m < 0 { m += total }
                return m
            }
            .sorted()
        var result: [CGFloat] = []
        for d in wrapped where (result.last.map { abs($0 - d) > 1e-6 } ?? true) {
            result.append(d)
        }
        return result
    }

    private static func cornerAnchoredHoles(
        along walker: PathWalkable,
        total: CGFloat,
        pitch: CGFloat,
        holeAngle: CGFloat,
        corners: [CGFloat]
    ) -> [StitchHole] {
        var holes: [StitchHole] = []

        if walker.isClosed {
            // Each corner is placed once as its span's start; the span wraps to the next
            // corner (the last span crosses the seam). No seam duplicate.
            let k = corners.count
            for i in 0..<k {
                let spanStart = corners[i]
                let spanEnd = (i + 1 < k) ? corners[i + 1] : corners[0] + total
                holes += fillSpanEvenly(
                    along: walker, total: total, spanStart: spanStart, spanLength: spanEnd - spanStart,
                    pitch: pitch, holeAngle: holeAngle, includeStart: true, includeEnd: false
                )
            }
        } else {
            // Open path: anchors are the two endpoints plus the interior corners. Both ends
            // get a hole; interior corners are placed once (as the next span's start).
            let interior = corners.filter { $0 > 1e-6 && $0 < total - 1e-6 }
            let anchors = [0] + interior + [total]
            for i in 0..<(anchors.count - 1) {
                let spanStart = anchors[i]
                let spanLength = anchors[i + 1] - spanStart
                let isLast = (i == anchors.count - 2)
                holes += fillSpanEvenly(
                    along: walker, total: total, spanStart: spanStart, spanLength: spanLength,
                    pitch: pitch, holeAngle: holeAngle, includeStart: true, includeEnd: isLast
                )
            }
        }

        return holes
    }

    /// Place exactly `count` holes on a cornered path: every anchor (corner, plus both
    /// endpoints on an open path) keeps its hole, and the remaining holes go to the span
    /// with the widest current interval, one at a time. The greedy choice minimizes the
    /// largest gap and is monotone in `count` — stepping N up by one re-divides a single
    /// span and leaves every other span's holes untouched. Counts below the anchor count
    /// are clamped up.
    private static func cornerConstrainedEvenCountHoles(
        along walker: PathWalkable,
        total: CGFloat,
        count: Int,
        holeAngle: CGFloat,
        corners: [CGFloat]
    ) -> [StitchHole] {
        var spans: [(start: CGFloat, length: CGFloat)] = []
        let anchorCount: Int
        if walker.isClosed {
            let k = corners.count
            anchorCount = k
            for i in 0..<k {
                let spanStart = corners[i]
                let spanEnd = (i + 1 < k) ? corners[i + 1] : corners[0] + total
                spans.append((spanStart, spanEnd - spanStart))
            }
        } else {
            let interior = corners.filter { $0 > 1e-6 && $0 < total - 1e-6 }
            let anchors = [0] + interior + [total]
            anchorCount = anchors.count
            for i in 0..<(anchors.count - 1) {
                spans.append((anchors[i], anchors[i + 1] - anchors[i]))
            }
        }

        var intervals = [Int](repeating: 1, count: spans.count)
        var remaining = max(count, anchorCount) - anchorCount
        while remaining > 0 {
            var best = 0
            var bestWidth = spans[0].length / CGFloat(intervals[0])
            for i in 1..<spans.count {
                let width = spans[i].length / CGFloat(intervals[i])
                if width > bestWidth {
                    best = i
                    bestWidth = width
                }
            }
            intervals[best] += 1
            remaining -= 1
        }

        var holes: [StitchHole] = []
        for (i, span) in spans.enumerated() {
            let isLast = (i == spans.count - 1)
            holes += fillSpan(
                along: walker, total: total, spanStart: span.start, spanLength: span.length,
                intervals: intervals[i], holeAngle: holeAngle,
                includeStart: true, includeEnd: !walker.isClosed && isLast
            )
        }
        return holes
    }

    /// Place evenly spaced holes within a span: `round(spanLength / pitch)` intervals,
    /// so spacing stays close to `pitch` while landing exactly on both span ends.
    private static func fillSpanEvenly(
        along walker: PathWalkable,
        total: CGFloat,
        spanStart: CGFloat,
        spanLength: CGFloat,
        pitch: CGFloat,
        holeAngle: CGFloat,
        includeStart: Bool,
        includeEnd: Bool
    ) -> [StitchHole] {
        fillSpan(
            along: walker, total: total, spanStart: spanStart, spanLength: spanLength,
            intervals: max(1, Int((spanLength / pitch).rounded())), holeAngle: holeAngle,
            includeStart: includeStart, includeEnd: includeEnd
        )
    }

    /// Split a span into `intervals` equal steps and emit holes on the step boundaries.
    private static func fillSpan(
        along walker: PathWalkable,
        total: CGFloat,
        spanStart: CGFloat,
        spanLength: CGFloat,
        intervals: Int,
        holeAngle: CGFloat,
        includeStart: Bool,
        includeEnd: Bool
    ) -> [StitchHole] {
        guard spanLength > 1e-9 else {
            return includeStart ? [hole(along: walker, total: total, distance: spanStart, holeAngle: holeAngle)] : []
        }

        let n = max(1, intervals)
        let step = spanLength / CGFloat(n)
        let lo = includeStart ? 0 : 1
        let hi = includeEnd ? n : n - 1
        guard lo <= hi else { return [] }

        var result: [StitchHole] = []
        for j in lo...hi {
            result.append(hole(along: walker, total: total, distance: spanStart + CGFloat(j) * step, holeAngle: holeAngle))
        }
        return result
    }

    private static func hole(along walker: PathWalkable, total: CGFloat, distance: CGFloat, holeAngle: CGFloat) -> StitchHole {
        var d = distance
        if d > total { d -= total }   // a closed span may wrap once past the seam
        else if d < 0 { d += total }
        let clamped = min(max(d, 0), total)
        let position = walker.pointAtDistance(clamped)
        let tangent = walker.tangentAtDistance(clamped)
        return StitchHole(position: position, angle: tangent + holeAngle)
    }

    // MARK: - Whole-path placement (smooth paths: line, circle, single curve)

    /// Fixed pitch: holes every `pitch` mm starting from distance 0. Used only for open
    /// smooth runs; the last hole may not land exactly on the path end.
    private static func fixedPitchHoles(
        along walker: PathWalkable,
        pitch: CGFloat,
        holeAngle: CGFloat
    ) -> [StitchHole] {
        let totalLength = walker.pathLength
        guard totalLength > 0, pitch > 0 else { return [] }

        var holes: [StitchHole] = []
        var d: CGFloat = 0
        while d <= totalLength + 1e-6 {
            let clampedD = min(d, totalLength)
            let position = walker.pointAtDistance(clampedD)
            let tangent = walker.tangentAtDistance(clampedD)
            holes.append(StitchHole(position: position, angle: tangent + holeAngle))
            d += pitch
        }
        return holes
    }

    /// Even count: exactly `count` holes spread evenly over the whole run, pitch ignored.
    /// Open path: both endpoints get a hole (count clamped to ≥ 2 so the ends exist).
    /// Closed path: holes are spread around the loop with no seam duplicate (count ≥ 1).
    private static func evenCountHoles(
        along walker: PathWalkable,
        count: Int,
        holeAngle: CGFloat
    ) -> [StitchHole] {
        let total = walker.pathLength
        guard total > 0 else { return [] }

        if walker.isClosed {
            let n = max(1, count)
            let step = total / CGFloat(n)
            return (0..<n).map { hole(along: walker, total: total, distance: CGFloat($0) * step, holeAngle: holeAngle) }
        } else {
            let n = max(2, count)
            let step = total / CGFloat(n - 1)
            return (0..<n).map {
                hole(along: walker, total: total, distance: min(CGFloat($0) * step, total), holeAngle: holeAngle)
            }
        }
    }

    /// Variable pitch: evenly distributed holes.
    /// Open path: holes land exactly on both endpoints; count is round(L / pitch) + 1.
    /// Closed path: holes are spread evenly around the loop with no seam duplicate.
    private static func variablePitchHoles(
        along walker: PathWalkable,
        targetPitch: CGFloat,
        holeAngle: CGFloat
    ) -> [StitchHole] {
        let totalLength = walker.pathLength
        guard totalLength > 0, targetPitch > 0 else { return [] }

        let n = max(1, Int(round(totalLength / targetPitch)))
        let adjustedPitch = totalLength / CGFloat(n)
        let lastIndex = walker.isClosed ? n - 1 : n

        var holes: [StitchHole] = []
        for i in 0...lastIndex {
            let d = CGFloat(i) * adjustedPitch
            let clampedD = min(d, totalLength)
            let position = walker.pointAtDistance(clampedD)
            let tangent = walker.tangentAtDistance(clampedD)
            holes.append(StitchHole(position: position, angle: tangent + holeAngle))
        }
        return holes
    }
}
