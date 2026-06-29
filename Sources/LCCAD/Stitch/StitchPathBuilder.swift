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
            var walkers: [PathWalkable] = [seed.walker]
            var ids: [UUID] = [seed.id]
            var startPoint = start(of: seed.walker)
            var endPoint = end(of: seed.walker)

            // Grow the chain forward from its tail, then backward from its head.
            extendForward(walkers: &walkers, ids: &ids, endPoint: &endPoint, remaining: &remaining)
            extendBackward(walkers: &walkers, ids: &ids, startPoint: &startPoint, remaining: &remaining)

            let isLoop = walkers.count >= 2 && close(startPoint, endPoint)
            let walker: PathWalkable = walkers.count == 1
                ? walkers[0]
                : CompositePathWalker(segments: walkers, isClosed: isLoop)
            paths.append(StitchPath(walker: walker, sourceShapeIds: ids))
        }

        return paths
    }

    private static func extendForward(
        walkers: inout [PathWalkable],
        ids: inout [UUID],
        endPoint: inout CGPoint,
        remaining: inout [(id: UUID, walker: PathWalkable)]
    ) {
        var matched = true
        while matched {
            matched = false
            for (idx, seg) in remaining.enumerated() {
                let segStart = start(of: seg.walker)
                let segEnd = end(of: seg.walker)
                if close(endPoint, segStart) {
                    walkers.append(seg.walker)
                    ids.append(seg.id)
                    endPoint = segEnd
                } else if close(endPoint, segEnd) {
                    walkers.append(ReversedPathWalker(inner: seg.walker))
                    ids.append(seg.id)
                    endPoint = segStart
                } else {
                    continue
                }
                remaining.remove(at: idx)
                matched = true
                break
            }
        }
    }

    private static func extendBackward(
        walkers: inout [PathWalkable],
        ids: inout [UUID],
        startPoint: inout CGPoint,
        remaining: inout [(id: UUID, walker: PathWalkable)]
    ) {
        var matched = true
        while matched {
            matched = false
            for (idx, seg) in remaining.enumerated() {
                let segStart = start(of: seg.walker)
                let segEnd = end(of: seg.walker)
                if close(startPoint, segEnd) {
                    walkers.insert(seg.walker, at: 0)
                    ids.insert(seg.id, at: 0)
                    startPoint = segStart
                } else if close(startPoint, segStart) {
                    walkers.insert(ReversedPathWalker(inner: seg.walker), at: 0)
                    ids.insert(seg.id, at: 0)
                    startPoint = segEnd
                } else {
                    continue
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
