import Foundation
import CoreGraphics

/// A candidate snap point with its type for visual indication.
struct SnapCandidate: Sendable {
    enum Kind: Sendable {
        case endpoint
        case midpoint
        case quarterPoint
        case center
        case intersection
        case gridPoint
    }

    let point: CGPoint
    let kind: Kind
}

struct SnapResult: Sendable {
    let snappedPoint: CGPoint
    let candidate: SnapCandidate?
}

struct SnapEngine {
    let tolerance: CGFloat  // snap distance in world coordinates
    let settings: ProjectSettings
    let layers: [Layer]
    let transform: CanvasTransform
    let excludedShapeIds: Set<UUID>

    init(tolerance: CGFloat, settings: ProjectSettings, layers: [Layer], transform: CanvasTransform, excludedShapeIds: Set<UUID> = []) {
        self.tolerance = tolerance
        self.settings = settings
        self.layers = layers
        self.transform = transform
        self.excludedShapeIds = excludedShapeIds
    }

    /// Find the best snap point near the given world point.
    func snap(_ point: CGPoint) -> SnapResult {
        var candidates: [SnapCandidate] = []

        // Collect snap points from all visible shapes (excluding ones the caller is moving)
        for layer in layers where layer.isVisible {
            for shape in layer.shapes {
                if excludedShapeIds.contains(shape.id) { continue }
                candidates.append(contentsOf: snapPoints(for: shape))
            }
        }

        // Collect intersection points between shapes
        candidates.append(contentsOf: intersectionPoints())

        // Grid snap — uses the same adaptive spacing as the visible grid
        if settings.snapToGrid {
            let gridRenderer = GridRenderer(settings: settings, transform: transform, colorScheme: .light)
            let (fineSpacing, _) = gridRenderer.adaptiveSpacings()
            let gridX = (point.x / fineSpacing).rounded() * fineSpacing
            let gridY = (point.y / fineSpacing).rounded() * fineSpacing
            candidates.append(SnapCandidate(point: CGPoint(x: gridX, y: gridY), kind: .gridPoint))
        }

        // Find closest candidate within tolerance
        var bestCandidate: SnapCandidate?
        var bestDist = tolerance

        for candidate in candidates {
            let dist = point.distance(to: candidate.point)
            if dist < bestDist {
                bestDist = dist
                bestCandidate = candidate
            }
        }

        if let best = bestCandidate {
            return SnapResult(snappedPoint: best.point, candidate: best)
        }
        return SnapResult(snappedPoint: point, candidate: nil)
    }

    // MARK: - Snap Points per Shape

    private func snapPoints(for shape: AnyShape) -> [SnapCandidate] {
        switch shape {
        case .line(let line):
            return lineSnapPoints(line)
        case .rectangle(let rect):
            return rectangleSnapPoints(rect)
        case .ellipse(let ellipse):
            return ellipseSnapPoints(ellipse)
        case .arc(let arc):
            return arcSnapPoints(arc)
        case .dot(let dot):
            return [SnapCandidate(point: dot.position, kind: .endpoint)]
        case .bezier(let bezier):
            return bezierSnapPoints(bezier)
        case .text(let text):
            return [SnapCandidate(point: text.position, kind: .endpoint)]
        case .group(let group):
            return group.children.flatMap { snapPoints(for: $0) }
        }
    }

    private func lineSnapPoints(_ line: LineShape) -> [SnapCandidate] {
        let mid = line.startPoint.midpoint(to: line.endPoint)
        let q1 = CGPoint(
            x: line.startPoint.x + (line.endPoint.x - line.startPoint.x) * 0.25,
            y: line.startPoint.y + (line.endPoint.y - line.startPoint.y) * 0.25
        )
        let q3 = CGPoint(
            x: line.startPoint.x + (line.endPoint.x - line.startPoint.x) * 0.75,
            y: line.startPoint.y + (line.endPoint.y - line.startPoint.y) * 0.75
        )
        return [
            SnapCandidate(point: line.startPoint, kind: .endpoint),
            SnapCandidate(point: line.endPoint, kind: .endpoint),
            SnapCandidate(point: mid, kind: .midpoint),
            SnapCandidate(point: q1, kind: .quarterPoint),
            SnapCandidate(point: q3, kind: .quarterPoint),
        ]
    }

    private func rectangleSnapPoints(_ rect: RectangleShape) -> [SnapCandidate] {
        let bb = rect.boundingBox
        return [
            // Corners
            SnapCandidate(point: CGPoint(x: bb.minX, y: bb.minY), kind: .endpoint),
            SnapCandidate(point: CGPoint(x: bb.maxX, y: bb.minY), kind: .endpoint),
            SnapCandidate(point: CGPoint(x: bb.minX, y: bb.maxY), kind: .endpoint),
            SnapCandidate(point: CGPoint(x: bb.maxX, y: bb.maxY), kind: .endpoint),
            // Edge midpoints
            SnapCandidate(point: CGPoint(x: bb.midX, y: bb.minY), kind: .midpoint),
            SnapCandidate(point: CGPoint(x: bb.midX, y: bb.maxY), kind: .midpoint),
            SnapCandidate(point: CGPoint(x: bb.minX, y: bb.midY), kind: .midpoint),
            SnapCandidate(point: CGPoint(x: bb.maxX, y: bb.midY), kind: .midpoint),
            // Center
            SnapCandidate(point: bb.center, kind: .center),
        ]
    }

    private func ellipseSnapPoints(_ ellipse: EllipseShape) -> [SnapCandidate] {
        [
            SnapCandidate(point: ellipse.center, kind: .center),
            SnapCandidate(point: CGPoint(x: ellipse.center.x + ellipse.radiusX, y: ellipse.center.y), kind: .endpoint),
            SnapCandidate(point: CGPoint(x: ellipse.center.x - ellipse.radiusX, y: ellipse.center.y), kind: .endpoint),
            SnapCandidate(point: CGPoint(x: ellipse.center.x, y: ellipse.center.y + ellipse.radiusY), kind: .endpoint),
            SnapCandidate(point: CGPoint(x: ellipse.center.x, y: ellipse.center.y - ellipse.radiusY), kind: .endpoint),
        ]
    }

    private func arcSnapPoints(_ arc: ArcShape) -> [SnapCandidate] {
        [
            SnapCandidate(point: arc.center, kind: .center),
            SnapCandidate(point: arc.startPoint, kind: .endpoint),
            SnapCandidate(point: arc.endPoint, kind: .endpoint),
        ]
    }

    private func bezierSnapPoints(_ bezier: BezierShape) -> [SnapCandidate] {
        var result: [SnapCandidate] = []
        for bp in bezier.points {
            result.append(SnapCandidate(point: bp.point, kind: .endpoint))
        }
        return result
    }

    // MARK: - Intersection Points

    private func intersectionPoints() -> [SnapCandidate] {
        var allLines: [(start: CGPoint, end: CGPoint)] = []
        for layer in layers where layer.isVisible {
            for shape in layer.shapes {
                if case .line(let line) = shape {
                    if excludedShapeIds.contains(line.id) { continue }
                    allLines.append((line.startPoint, line.endPoint))
                }
            }
        }

        var results: [SnapCandidate] = []
        for i in 0..<allLines.count {
            for j in (i + 1)..<allLines.count {
                if let pt = Intersection.lineLineIntersection(
                    a1: allLines[i].start, a2: allLines[i].end,
                    b1: allLines[j].start, b2: allLines[j].end
                ) {
                    results.append(SnapCandidate(point: pt, kind: .intersection))
                }
            }
        }
        return results
    }
}
