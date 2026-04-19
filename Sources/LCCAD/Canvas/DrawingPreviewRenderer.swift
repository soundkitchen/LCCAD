import SwiftUI

enum DrawingPreviewRenderer {
    static let previewColor = Color.accentColor
    static let previewLineWidth: CGFloat = 1.0
    static let startPointRadius: CGFloat = 4.0

    static func draw(preview: DrawingPreview?, transform: CanvasTransform, in context: GraphicsContext) {
        guard let preview else { return }

        switch preview {
        case .startPoint(let point):
            drawStartPoint(point, transform: transform, in: context)

        case .lineFromClick(let start, let end):
            drawStartPoint(start, transform: transform, in: context)
            drawPreviewLine(from: start, to: end, transform: transform, in: context)
            drawEndCrosshair(end, transform: transform, in: context)

        case .lineFromDrag(let start, let end):
            drawStartPoint(start, transform: transform, in: context)
            drawPreviewLine(from: start, to: end, transform: transform, in: context)
            drawLengthLabel(from: start, to: end, transform: transform, in: context)

        case .rectangle(let origin, let size):
            drawPreviewRectangle(origin: origin, size: size, transform: transform, in: context)
            drawSizeLabel(size: size, origin: origin, transform: transform, in: context)

        case .ellipsePreview(let center, let radiusX, let radiusY):
            drawPreviewEllipse(center: center, radiusX: radiusX, radiusY: radiusY, transform: transform, in: context)
            let size = CGSize(width: radiusX * 2, height: radiusY * 2)
            let origin = CGPoint(x: center.x - radiusX, y: center.y - radiusY)
            drawSizeLabel(size: size, origin: origin, transform: transform, in: context)

        case .arcPreview(let center, let radius, let startAngle, let endAngle, let clockwise):
            drawPreviewArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise, transform: transform, in: context)

        case .bezierPreview(let points, let currentPoint):
            drawPreviewBezier(points: points, currentPoint: currentPoint, transform: transform, in: context)

        case .twoPoints(let p1, let p2):
            drawStartPoint(p1, transform: transform, in: context)
            drawStartPoint(p2, transform: transform, in: context)
            drawPreviewLine(from: p1, to: p2, transform: transform, in: context)
        }
    }

    // MARK: - Start Point (pulsing dot)

    private static func drawStartPoint(_ point: CGPoint, transform: CanvasTransform, in context: GraphicsContext) {
        let screenPoint = transform.worldToScreen(point)

        // Outer ring
        let outerRect = CGRect(
            x: screenPoint.x - startPointRadius - 2,
            y: screenPoint.y - startPointRadius - 2,
            width: (startPointRadius + 2) * 2,
            height: (startPointRadius + 2) * 2
        )
        context.stroke(
            Path(ellipseIn: outerRect),
            with: .color(previewColor.opacity(0.4)),
            lineWidth: 1
        )

        // Inner filled dot
        let innerRect = CGRect(
            x: screenPoint.x - startPointRadius,
            y: screenPoint.y - startPointRadius,
            width: startPointRadius * 2,
            height: startPointRadius * 2
        )
        context.fill(Path(ellipseIn: innerRect), with: .color(previewColor))
    }

    // MARK: - Preview Line

    private static func drawPreviewLine(from start: CGPoint, to end: CGPoint, transform: CanvasTransform, in context: GraphicsContext) {
        let screenStart = transform.worldToScreen(start)
        let screenEnd = transform.worldToScreen(end)

        let path = Path { p in
            p.move(to: screenStart)
            p.addLine(to: screenEnd)
        }
        context.stroke(
            path,
            with: .color(previewColor),
            style: SwiftUI.StrokeStyle(lineWidth: previewLineWidth, dash: [6, 3])
        )
    }

    // MARK: - End Crosshair (for click-based line drawing)

    private static func drawEndCrosshair(_ point: CGPoint, transform: CanvasTransform, in context: GraphicsContext) {
        let screenPoint = transform.worldToScreen(point)
        let armLength: CGFloat = 8

        let hPath = Path { p in
            p.move(to: CGPoint(x: screenPoint.x - armLength, y: screenPoint.y))
            p.addLine(to: CGPoint(x: screenPoint.x + armLength, y: screenPoint.y))
        }
        let vPath = Path { p in
            p.move(to: CGPoint(x: screenPoint.x, y: screenPoint.y - armLength))
            p.addLine(to: CGPoint(x: screenPoint.x, y: screenPoint.y + armLength))
        }

        context.stroke(hPath, with: .color(previewColor.opacity(0.6)), lineWidth: 0.5)
        context.stroke(vPath, with: .color(previewColor.opacity(0.6)), lineWidth: 0.5)
    }

    // MARK: - Preview Rectangle

    private static func drawPreviewRectangle(origin: CGPoint, size: CGSize, transform: CanvasTransform, in context: GraphicsContext) {
        let worldRect = CGRect(origin: origin, size: size)
        let screenRect = transform.worldToScreen(worldRect)

        // Dashed outline
        let path = Path(roundedRect: screenRect, cornerRadius: 0)
        context.stroke(
            path,
            with: .color(previewColor),
            style: SwiftUI.StrokeStyle(lineWidth: previewLineWidth, dash: [6, 3])
        )

        // Semi-transparent fill
        context.fill(path, with: .color(previewColor.opacity(0.05)))
    }

    // MARK: - Preview Ellipse

    private static func drawPreviewEllipse(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, transform: CanvasTransform, in context: GraphicsContext) {
        let worldRect = CGRect(x: center.x - radiusX, y: center.y - radiusY, width: radiusX * 2, height: radiusY * 2)
        let screenRect = transform.worldToScreen(worldRect)

        let path = Path(ellipseIn: screenRect)
        context.stroke(
            path,
            with: .color(previewColor),
            style: SwiftUI.StrokeStyle(lineWidth: previewLineWidth, dash: [6, 3])
        )
        context.fill(path, with: .color(previewColor.opacity(0.05)))

        // Center crosshair
        let screenCenter = transform.worldToScreen(center)
        drawEndCrosshair(center, transform: transform, in: context)
        _ = screenCenter
    }

    // MARK: - Preview Arc

    private static func drawPreviewArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CanvasTransform, in context: GraphicsContext) {
        let screenCenter = transform.worldToScreen(center)
        let screenRadius = transform.worldToScreenDistance(radius)

        let path = Path { p in
            p.addArc(center: screenCenter, radius: screenRadius, startAngle: .radians(startAngle), endAngle: .radians(endAngle), clockwise: clockwise)
        }
        context.stroke(
            path,
            with: .color(previewColor),
            style: SwiftUI.StrokeStyle(lineWidth: previewLineWidth, dash: [6, 3])
        )

        // Show center
        drawEndCrosshair(center, transform: transform, in: context)

        // Radius label
        let label = String(format: "R %.1f mm", radius)
        let labelPos = CGPoint(x: screenCenter.x, y: screenCenter.y - 14)
        context.draw(
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(previewColor),
            at: labelPos,
            anchor: .center
        )
    }

    // MARK: - Preview Bezier

    private static func drawPreviewBezier(points: [BezierPoint], currentPoint: CGPoint, transform: CanvasTransform, in context: GraphicsContext) {
        guard !points.isEmpty else { return }

        // Draw committed segments
        if points.count >= 2 {
            let path = Path { p in
                let first = transform.worldToScreen(points[0].point)
                p.move(to: first)
                for i in 0..<(points.count - 1) {
                    let cp1 = transform.worldToScreen(points[i].controlOut)
                    let cp2 = transform.worldToScreen(points[i + 1].controlIn)
                    let end = transform.worldToScreen(points[i + 1].point)
                    p.addCurve(to: end, control1: cp1, control2: cp2)
                }
            }
            context.stroke(path, with: .color(previewColor), style: SwiftUI.StrokeStyle(lineWidth: previewLineWidth))
        }

        // Draw preview segment from last point to cursor (curve using controlOut)
        let last = points.last!
        let screenLast = transform.worldToScreen(last.point)
        let screenCurrent = transform.worldToScreen(currentPoint)
        let screenCP1 = transform.worldToScreen(last.controlOut)
        let previewPath = Path { p in
            p.move(to: screenLast)
            p.addCurve(to: screenCurrent, control1: screenCP1, control2: screenCurrent)
        }
        context.stroke(previewPath, with: .color(previewColor.opacity(0.5)), style: SwiftUI.StrokeStyle(lineWidth: previewLineWidth, dash: [4, 3]))

        // Draw control handle lines for points with non-collapsed handles
        for bp in points {
            guard bp.controlOut != bp.point || bp.controlIn != bp.point else { continue }
            let screenAnchor = transform.worldToScreen(bp.point)
            let screenCtrlIn = transform.worldToScreen(bp.controlIn)
            let screenCtrlOut = transform.worldToScreen(bp.controlOut)
            let tangentPath = Path { p in
                p.move(to: screenCtrlIn)
                p.addLine(to: screenAnchor)
                p.addLine(to: screenCtrlOut)
            }
            context.stroke(tangentPath, with: .color(previewColor.opacity(0.5)), lineWidth: 0.75)
            let r: CGFloat = 3.0
            for pt in [screenCtrlIn, screenCtrlOut] {
                let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(previewColor))
            }
        }

        // Draw anchor points
        for bp in points {
            drawStartPoint(bp.point, transform: transform, in: context)
        }

        // Cursor crosshair
        drawEndCrosshair(currentPoint, transform: transform, in: context)
    }

    // MARK: - Measurement Labels

    private static func drawLengthLabel(from start: CGPoint, to end: CGPoint, transform: CanvasTransform, in context: GraphicsContext) {
        let length = start.distance(to: end)
        let label = String(format: "%.1f mm", length)

        let midScreen = transform.worldToScreen(start.midpoint(to: end))
        let offset = CGPoint(x: midScreen.x, y: midScreen.y - 14)

        context.draw(
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(previewColor),
            at: offset,
            anchor: .center
        )
    }

    private static func drawSizeLabel(size: CGSize, origin: CGPoint, transform: CanvasTransform, in context: GraphicsContext) {
        let label = String(format: "%.1f × %.1f mm", size.width, size.height)

        let worldRect = CGRect(origin: origin, size: size)
        let screenRect = transform.worldToScreen(worldRect)
        let labelPos = CGPoint(x: screenRect.midX, y: screenRect.maxY + 14)

        context.draw(
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(previewColor),
            at: labelPos,
            anchor: .center
        )
    }
}
