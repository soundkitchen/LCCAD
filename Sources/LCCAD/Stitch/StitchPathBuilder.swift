import Foundation
import CoreGraphics

/// Turns a set of leaf shapes into stitch paths.
///
/// - Closed shapes (rectangle, ellipse/circle, closed bezier) each become their own
///   closed path.
/// - Open segments (line, arc, open bezier) are welded together by matching endpoints:
///   adjacent segments that share an endpoint (within `weldTolerance`) are chained into
///   one continuous path, reversing a segment's direction when needed so the chain runs
///   head-to-tail. A chain whose two free ends meet becomes a closed loop.
///
/// This is what lets a part outline drawn as several connected lines/arcs/curves be
/// stitched as a single continuous run — the foundation for matched (駒合わせ) stitching
/// across inner/outer parts.
enum StitchPathBuilder {
    /// Maximum gap (mm) between two endpoints for them to be considered connected.
    /// Snapped drawings coincide exactly; this absorbs floating-point noise.
    static let weldTolerance: CGFloat = 0.1

    /// A resolved stitch run: a walkable path plus the source shape ids that compose it,
    /// in path order.
    struct StitchPath {
        let walker: PathWalkable
        let sourceShapeIds: [UUID]
    }

    static func build(from shapes: [AnyShape]) -> [StitchPath] {
        var paths: [StitchPath] = []
        var openSegments: [(id: UUID, walker: PathWalkable)] = []

        for shape in shapes {
            guard let walker = PathWalkerFactory.walker(for: shape), walker.pathLength > 0 else { continue }
            if walker.isClosed {
                paths.append(StitchPath(walker: walker, sourceShapeIds: [shape.id]))
            } else {
                openSegments.append((shape.id, walker))
            }
        }

        paths.append(contentsOf: weld(openSegments))
        return paths
    }

    // MARK: - Welding

    private static func weld(_ segments: [(id: UUID, walker: PathWalkable)]) -> [StitchPath] {
        var remaining = segments
        var paths: [StitchPath] = []

        while !remaining.isEmpty {
            let seed = remaining.removeFirst()
            var chain = Chain(
                walkers: [seed.walker],
                ids: [seed.id],
                start: start(of: seed.walker),
                end: end(of: seed.walker)
            )

            // Grow from the tail, then from the head. Growth stops as soon as the chain
            // closes into a loop, so a stray segment touching the seam isn't pulled in
            // (which would otherwise emit a closed outline as an open path).
            grow(&chain, atTail: true, remaining: &remaining)
            grow(&chain, atTail: false, remaining: &remaining)

            let isLoop = chain.walkers.count >= 2 && close(chain.start, chain.end)
            let walker: PathWalkable = chain.walkers.count == 1
                ? chain.walkers[0]
                : CompositePathWalker(segments: chain.walkers, isClosed: isLoop)
            paths.append(StitchPath(walker: walker, sourceShapeIds: chain.ids))
        }

        return paths
    }

    private struct Chain {
        var walkers: [PathWalkable]
        var ids: [UUID]
        var start: CGPoint
        var end: CGPoint
    }

    /// Attach connecting segments to one end of the chain, reversing a segment's
    /// direction when needed so the chain runs head-to-tail. Stops once the chain has
    /// closed into a loop.
    private static func grow(
        _ chain: inout Chain,
        atTail: Bool,
        remaining: inout [(id: UUID, walker: PathWalkable)]
    ) {
        var matched = true
        while matched {
            matched = false
            if chain.walkers.count >= 2 && close(chain.start, chain.end) { return }

            let anchor = atTail ? chain.end : chain.start
            for (idx, seg) in remaining.enumerated() {
                let segStart = start(of: seg.walker)
                let segEnd = end(of: seg.walker)
                let attached: PathWalkable
                let freeEnd: CGPoint
                if atTail {
                    // Append so the new segment's start meets the chain's end.
                    if close(anchor, segStart) { attached = seg.walker; freeEnd = segEnd }
                    else if close(anchor, segEnd) { attached = ReversedPathWalker(inner: seg.walker); freeEnd = segStart }
                    else { continue }
                    chain.walkers.append(attached)
                    chain.ids.append(seg.id)
                    chain.end = freeEnd
                } else {
                    // Prepend so the new segment's end meets the chain's start.
                    if close(anchor, segEnd) { attached = seg.walker; freeEnd = segStart }
                    else if close(anchor, segStart) { attached = ReversedPathWalker(inner: seg.walker); freeEnd = segEnd }
                    else { continue }
                    chain.walkers.insert(attached, at: 0)
                    chain.ids.insert(seg.id, at: 0)
                    chain.start = freeEnd
                }
                remaining.remove(at: idx)
                matched = true
                break
            }
        }
    }

    private static func start(of walker: PathWalkable) -> CGPoint { walker.pointAtDistance(0) }
    private static func end(of walker: PathWalkable) -> CGPoint { walker.pointAtDistance(walker.pathLength) }
    private static func close(_ a: CGPoint, _ b: CGPoint) -> Bool { a.distance(to: b) <= weldTolerance }
}
