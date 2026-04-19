import SwiftUI

enum SnapOverlay {
    static let snapColor = Color.green
    static let snapRadius: CGFloat = 5

    static func draw(candidate: SnapCandidate?, transform: CanvasTransform, in context: GraphicsContext) {
        guard let candidate else { return }

        let screenPoint = transform.worldToScreen(candidate.point)

        switch candidate.kind {
        case .endpoint:
            drawDiamond(at: screenPoint, in: context)
        case .midpoint:
            drawTriangle(at: screenPoint, in: context)
        case .quarterPoint:
            drawSmallDot(at: screenPoint, in: context)
        case .center:
            drawCrosshair(at: screenPoint, in: context)
        case .intersection:
            drawX(at: screenPoint, in: context)
        case .gridPoint:
            drawSmallDot(at: screenPoint, in: context)
        }
    }

    // Diamond for endpoints
    private static func drawDiamond(at point: CGPoint, in context: GraphicsContext) {
        let s = snapRadius
        let path = Path { p in
            p.move(to: CGPoint(x: point.x, y: point.y - s))
            p.addLine(to: CGPoint(x: point.x + s, y: point.y))
            p.addLine(to: CGPoint(x: point.x, y: point.y + s))
            p.addLine(to: CGPoint(x: point.x - s, y: point.y))
            p.closeSubpath()
        }
        context.stroke(path, with: .color(snapColor), lineWidth: 1.5)
    }

    // Triangle for midpoints
    private static func drawTriangle(at point: CGPoint, in context: GraphicsContext) {
        let s = snapRadius
        let path = Path { p in
            p.move(to: CGPoint(x: point.x, y: point.y - s))
            p.addLine(to: CGPoint(x: point.x + s, y: point.y + s))
            p.addLine(to: CGPoint(x: point.x - s, y: point.y + s))
            p.closeSubpath()
        }
        context.stroke(path, with: .color(snapColor), lineWidth: 1.5)
    }

    // Small dot for quarter/grid
    private static func drawSmallDot(at point: CGPoint, in context: GraphicsContext) {
        let r: CGFloat = 3
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: rect), with: .color(snapColor))
    }

    // Crosshair for centers
    private static func drawCrosshair(at point: CGPoint, in context: GraphicsContext) {
        let s = snapRadius + 2
        let h = Path { p in
            p.move(to: CGPoint(x: point.x - s, y: point.y))
            p.addLine(to: CGPoint(x: point.x + s, y: point.y))
        }
        let v = Path { p in
            p.move(to: CGPoint(x: point.x, y: point.y - s))
            p.addLine(to: CGPoint(x: point.x, y: point.y + s))
        }
        context.stroke(h, with: .color(snapColor), lineWidth: 1)
        context.stroke(v, with: .color(snapColor), lineWidth: 1)

        let r: CGFloat = 3
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(snapColor), lineWidth: 1)
    }

    // X for intersections
    private static func drawX(at point: CGPoint, in context: GraphicsContext) {
        let s = snapRadius
        let p1 = Path { p in
            p.move(to: CGPoint(x: point.x - s, y: point.y - s))
            p.addLine(to: CGPoint(x: point.x + s, y: point.y + s))
        }
        let p2 = Path { p in
            p.move(to: CGPoint(x: point.x + s, y: point.y - s))
            p.addLine(to: CGPoint(x: point.x - s, y: point.y + s))
        }
        context.stroke(p1, with: .color(snapColor), lineWidth: 1.5)
        context.stroke(p2, with: .color(snapColor), lineWidth: 1.5)
    }
}
