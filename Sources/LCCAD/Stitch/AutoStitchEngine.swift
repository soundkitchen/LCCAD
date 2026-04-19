import Foundation
import CoreGraphics

enum AutoStitchEngine {
    /// Generate stitch holes along a walkable path using the given pricking iron.
    static func generateHoles(
        along walker: PathWalkable,
        iron: PrickingIron,
        mode: StitchMode = .fixedPitch
    ) -> [StitchHole] {
        switch mode {
        case .fixedPitch:
            return fixedPitchHoles(along: walker, pitch: iron.pitch, holeAngle: iron.holeAngle)
        case .variablePitch:
            return variablePitchHoles(along: walker, targetPitch: iron.pitch, holeAngle: iron.holeAngle)
        }
    }

    /// Fixed pitch: holes every `pitch` mm starting from distance 0.
    /// Last hole may not land exactly on the path end.
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

    /// Variable pitch: adjusts spacing so holes land exactly on both endpoints.
    /// Total hole count is round(totalLength / targetPitch) + 1.
    private static func variablePitchHoles(
        along walker: PathWalkable,
        targetPitch: CGFloat,
        holeAngle: CGFloat
    ) -> [StitchHole] {
        let totalLength = walker.pathLength
        guard totalLength > 0, targetPitch > 0 else { return [] }

        let n = max(1, Int(round(totalLength / targetPitch)))
        let adjustedPitch = totalLength / CGFloat(n)

        var holes: [StitchHole] = []
        for i in 0...n {
            let d = CGFloat(i) * adjustedPitch
            let clampedD = min(d, totalLength)
            let position = walker.pointAtDistance(clampedD)
            let tangent = walker.tangentAtDistance(clampedD)
            holes.append(StitchHole(position: position, angle: tangent + holeAngle))
        }

        return holes
    }
}
