import SwiftUI

enum SelectionOverlay {
    static let handleSize: CGFloat = 8
    static let handleColor = Color(red: 0.29, green: 0.56, blue: 0.85) // #4A90D9

    static func draw(boundingBox: CGRect, transform: CanvasTransform, in context: GraphicsContext) {
        let screenRect = transform.worldToScreen(boundingBox)

        // Draw bounding box outline
        let boxPath = Path(screenRect)
        context.stroke(boxPath, with: .color(handleColor), style: SwiftUI.StrokeStyle(lineWidth: 1, dash: [4, 3]))

        // Draw corner handles
        let corners = [
            CGPoint(x: screenRect.minX, y: screenRect.minY),
            CGPoint(x: screenRect.maxX, y: screenRect.minY),
            CGPoint(x: screenRect.minX, y: screenRect.maxY),
            CGPoint(x: screenRect.maxX, y: screenRect.maxY),
        ]

        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(Path(handleRect), with: .color(handleColor))
            context.stroke(Path(handleRect), with: .color(.white), lineWidth: 1)
        }
    }

    // MARK: - Bezier Point Edit Overlay

    static func drawBezierEditOverlay(
        bezier: BezierShape,
        transform: CanvasTransform,
        draggingIndex: Int?,
        draggingTarget: BezierDragTarget?,
        in context: GraphicsContext
    ) {
        let anchorSize: CGFloat = 6
        let handleRadius: CGFloat = 3.5

        // 1. Control handle lines and circles
        for (i, bp) in bezier.points.enumerated() {
            let screenAnchor = transform.worldToScreen(bp.point)
            let isDraggingThis = draggingIndex == i

            // controlIn handle
            if bp.controlIn != bp.point {
                let screenCtrlIn = transform.worldToScreen(bp.controlIn)
                let linePath = Path { p in
                    p.move(to: screenAnchor)
                    p.addLine(to: screenCtrlIn)
                }
                context.stroke(linePath, with: .color(handleColor.opacity(0.5)), lineWidth: 0.75)

                let isActive = isDraggingThis && draggingTarget == .controlIn
                let r = isActive ? handleRadius + 1 : handleRadius
                let rect = CGRect(x: screenCtrlIn.x - r, y: screenCtrlIn.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(isActive ? .white : handleColor))
                context.stroke(Path(ellipseIn: rect), with: .color(handleColor), lineWidth: 1)
            }

            // controlOut handle
            if bp.controlOut != bp.point {
                let screenCtrlOut = transform.worldToScreen(bp.controlOut)
                let linePath = Path { p in
                    p.move(to: screenAnchor)
                    p.addLine(to: screenCtrlOut)
                }
                context.stroke(linePath, with: .color(handleColor.opacity(0.5)), lineWidth: 0.75)

                let isActive = isDraggingThis && draggingTarget == .controlOut
                let r = isActive ? handleRadius + 1 : handleRadius
                let rect = CGRect(x: screenCtrlOut.x - r, y: screenCtrlOut.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(isActive ? .white : handleColor))
                context.stroke(Path(ellipseIn: rect), with: .color(handleColor), lineWidth: 1)
            }
        }

        // 2. Anchor point squares (drawn last, on top)
        for (i, bp) in bezier.points.enumerated() {
            let screen = transform.worldToScreen(bp.point)
            let isActive = draggingIndex == i && draggingTarget == .anchor
            let s = isActive ? anchorSize + 2 : anchorSize
            let rect = CGRect(x: screen.x - s / 2, y: screen.y - s / 2, width: s, height: s)
            context.fill(Path(rect), with: .color(isActive ? .white : handleColor))
            context.stroke(Path(rect), with: .color(handleColor), lineWidth: 1)
        }
    }
}
