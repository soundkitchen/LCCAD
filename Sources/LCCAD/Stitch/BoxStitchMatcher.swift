import Foundation
import CoreGraphics

/// How the shared hole count for a matched (駒合わせ) pair is chosen.
enum BoxStitchPolicy: Equatable {
    /// Use the larger of the two parts' natural counts.
    case matchLarger
    /// Use the smaller of the two parts' natural counts.
    case matchSmaller
    /// Use a user-specified count.
    case custom(Int)
}

/// Count analysis for a two-part matched stitch: the pitch-driven natural count of each
/// part and the smallest shared count both parts can honor (every corner anchor keeps
/// its hole, open runs keep both endpoints).
struct BoxStitchProposal: Equatable {
    let naturalCountA: Int
    let naturalCountB: Int
    let minimumCount: Int

    /// The shared count a policy resolves to, clamped so both parts can honor it.
    func resolvedCount(for policy: BoxStitchPolicy) -> Int {
        let raw: Int
        switch policy {
        case .matchLarger:
            raw = max(naturalCountA, naturalCountB)
        case .matchSmaller:
            raw = min(naturalCountA, naturalCountB)
        case .custom(let n):
            raw = n
        }
        return max(raw, minimumCount)
    }
}

enum BoxStitchMatcher {
    /// Proposal for matching hole counts across exactly two stitch runs; nil otherwise.
    /// Path order follows the input; callers decide which run is A and which is B.
    static func proposal(for paths: [StitchPathBuilder.StitchPath], iron: PrickingIron) -> BoxStitchProposal? {
        guard paths.count == 2 else { return nil }
        let a = paths[0].walker
        let b = paths[1].walker
        return BoxStitchProposal(
            naturalCountA: AutoStitchEngine.naturalHoleCount(along: a, iron: iron),
            naturalCountB: AutoStitchEngine.naturalHoleCount(along: b, iron: iron),
            minimumCount: max(
                AutoStitchEngine.minimumHoleCount(along: a),
                AutoStitchEngine.minimumHoleCount(along: b)
            )
        )
    }
}
