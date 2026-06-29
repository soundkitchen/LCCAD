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
    /// - Closed smooth paths (circle, ellipse, smooth blob): holes are spread evenly around
    ///   the loop with no seam duplicate.
    /// - Open smooth paths (a single line or open curve): `Fixed` keeps an exact pitch from
    ///   the start; `Variable` evens the spacing so holes land on both ends.
    static func generateHoles(
        along walker: PathWalkable,
        iron: PrickingIron,
        mode: StitchMode = .fixedPitch
    ) -> [StitchHole] {
        let total = walker.pathLength
        guard total > 0, iron.pitch > 0 else { return [] }

        let corners = normalizedCorners(walker.cornerDistances, total: total)
        if !corners.isEmpty {
            return cornerAnchoredHoles(
                along: walker, total: total, pitch: iron.pitch, holeAngle: iron.holeAngle, corners: corners
            )
        }

        // No corners: a smooth path. Closed loops are always evened (a fixed march would
        // cluster at the seam); open runs honor the selected mode.
        if walker.isClosed {
            return variablePitchHoles(along: walker, targetPitch: iron.pitch, holeAngle: iron.holeAngle)
        }
        switch mode {
        case .fixedPitch:
            return fixedPitchHoles(along: walker, pitch: iron.pitch, holeAngle: iron.holeAngle)
        case .variablePitch:
            return variablePitchHoles(along: walker, targetPitch: iron.pitch, holeAngle: iron.holeAngle)
        }
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
        guard spanLength > 1e-9 else {
            return includeStart ? [hole(along: walker, total: total, distance: spanStart, holeAngle: holeAngle)] : []
        }

        let n = max(1, Int((spanLength / pitch).rounded()))
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
