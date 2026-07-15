import SwiftUI

struct CanvasRenderer {
    let transform: CanvasTransform
    var colorScheme: ColorScheme = .light
    var unit: LengthUnit = .millimeters

    func draw(shape: AnyShape, in context: GraphicsContext) {
        let sc = shape.stroke.color
        let color = Color(red: sc.r, green: sc.g, blue: sc.b, opacity: sc.a)
        // Ensure lines are always visible (min 0.75px) but scale with zoom
        let scaledWidth = transform.worldToScreenDistance(shape.stroke.width)
        let lineWidth = max(0.75, min(scaledWidth, 4.0))
        let dash: [CGFloat] = (shape.stroke.dashPattern ?? [])
            .map { max(1, transform.worldToScreenDistance($0)) }
        let strokeStyle = SwiftUI.StrokeStyle(lineWidth: lineWidth, dash: dash)

        switch shape {
        case .line(let line):
            drawLine(line, color: color, strokeStyle: strokeStyle, in: context)
        case .rectangle(let rect):
            drawRectangle(rect, color: color, strokeStyle: strokeStyle, in: context)
        case .ellipse(let ellipse):
            drawEllipse(ellipse, color: color, strokeStyle: strokeStyle, in: context)
        case .arc(let arc):
            drawArc(arc, color: color, strokeStyle: strokeStyle, in: context)
        case .dot(let dot):
            drawDot(dot, color: color, in: context)
        case .bezier(let bezier):
            drawBezier(bezier, color: color, strokeStyle: strokeStyle, in: context)
        case .text(let text):
            drawText(text, color: color, in: context)
        case .dimensionLine(let dim):
            drawDimension(dim, in: context)
        case .group(let group):
            for child in group.children {
                draw(shape: child, in: context)
            }
        }
    }

    private func drawLine(_ line: LineShape, color: Color, strokeStyle: SwiftUI.StrokeStyle, in context: GraphicsContext) {
        let start = transform.worldToScreen(line.startPoint)
        let end = transform.worldToScreen(line.endPoint)
        let path = Path { p in
            p.move(to: start)
            p.addLine(to: end)
        }
        context.stroke(path, with: .color(color), style: strokeStyle)
    }

    private func drawRectangle(_ rect: RectangleShape, color: Color, strokeStyle: SwiftUI.StrokeStyle, in context: GraphicsContext) {
        let unrotatedWorld = CGRect(origin: rect.origin, size: rect.size)
        let screenRect = transform.worldToScreen(unrotatedWorld)
        let cr = transform.worldToScreenDistance(rect.cornerRadius)
        var path = Path(roundedRect: screenRect, cornerRadius: cr)
        if rect.rotation != 0 {
            let centerScreen = transform.worldToScreen(rect.unrotatedCenter)
            let t = CGAffineTransform(translationX: centerScreen.x, y: centerScreen.y)
                .rotated(by: rect.rotation)
                .translatedBy(x: -centerScreen.x, y: -centerScreen.y)
            path = path.applying(t)
        }
        context.stroke(path, with: .color(color), style: strokeStyle)
    }

    private func drawEllipse(_ ellipse: EllipseShape, color: Color, strokeStyle: SwiftUI.StrokeStyle, in context: GraphicsContext) {
        let screenRect = transform.worldToScreen(ellipse.unrotatedBounds)
        var path = Path(ellipseIn: screenRect)
        if ellipse.rotation != 0 {
            let centerScreen = transform.worldToScreen(ellipse.center)
            let t = CGAffineTransform(translationX: centerScreen.x, y: centerScreen.y)
                .rotated(by: ellipse.rotation)
                .translatedBy(x: -centerScreen.x, y: -centerScreen.y)
            path = path.applying(t)
        }
        context.stroke(path, with: .color(color), style: strokeStyle)
    }

    private func drawArc(_ arc: ArcShape, color: Color, strokeStyle: SwiftUI.StrokeStyle, in context: GraphicsContext) {
        let center = transform.worldToScreen(arc.center)
        let radius = transform.worldToScreenDistance(arc.radius)
        let path = Path { p in
            p.addArc(center: center, radius: radius, startAngle: .radians(arc.startAngle), endAngle: .radians(arc.endAngle), clockwise: arc.clockwise)
        }
        context.stroke(path, with: .color(color), style: strokeStyle)
    }

    private func drawDot(_ dot: DotShape, color: Color, in context: GraphicsContext) {
        let center = transform.worldToScreen(dot.position)
        let radius = max(2, transform.worldToScreenDistance(dot.radius))
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    private func drawBezier(_ bezier: BezierShape, color: Color, strokeStyle: SwiftUI.StrokeStyle, in context: GraphicsContext) {
        guard bezier.points.count >= 2 else { return }
        let path = Path { p in
            let first = transform.worldToScreen(bezier.points[0].point)
            p.move(to: first)

            let segmentCount = bezier.isClosed ? bezier.points.count : bezier.points.count - 1
            for i in 0..<segmentCount {
                let j = (i + 1) % bezier.points.count
                let cp1 = transform.worldToScreen(bezier.points[i].controlOut)
                let cp2 = transform.worldToScreen(bezier.points[j].controlIn)
                let end = transform.worldToScreen(bezier.points[j].point)
                p.addCurve(to: end, control1: cp1, control2: cp2)
            }
            if bezier.isClosed { p.closeSubpath() }
        }
        context.stroke(path, with: .color(color), style: strokeStyle)
    }

    // MARK: - Stitch Hole Rendering

    func drawStitchHole(_ hole: StitchHole, holeType: HoleType, holeSize: CGFloat,
                        tint: Color? = nil, in context: GraphicsContext) {
        let center = transform.worldToScreen(hole.position)
        let screenSize = max(3, transform.worldToScreenDistance(holeSize))
        let stitchColor = tint ?? DesignTokens.stitchColor

        switch holeType {
        case .diamond:
            let half = screenSize / 2
            let angle = hole.angle
            let cos_a = cos(angle)
            let sin_a = sin(angle)
            let path = Path { p in
                p.move(to: CGPoint(x: center.x + half * cos_a, y: center.y + half * sin_a))
                p.addLine(to: CGPoint(x: center.x - half * sin_a, y: center.y + half * cos_a))
                p.addLine(to: CGPoint(x: center.x - half * cos_a, y: center.y - half * sin_a))
                p.addLine(to: CGPoint(x: center.x + half * sin_a, y: center.y - half * cos_a))
                p.closeSubpath()
            }
            context.fill(path, with: .color(stitchColor))

        case .round:
            let rect = CGRect(
                x: center.x - screenSize / 2, y: center.y - screenSize / 2,
                width: screenSize, height: screenSize
            )
            context.fill(Path(ellipseIn: rect), with: .color(stitchColor))

        case .flat:
            let w = screenSize
            let h = screenSize * 0.4
            let angle = hole.angle
            let cos_a = cos(angle)
            let sin_a = sin(angle)
            let path = Path { p in
                let hw = w / 2, hh = h / 2
                let corners = [
                    CGPoint(x: hw, y: -hh), CGPoint(x: hw, y: hh),
                    CGPoint(x: -hw, y: hh), CGPoint(x: -hw, y: -hh),
                ]
                let rotated = corners.map { pt in
                    CGPoint(x: center.x + pt.x * cos_a - pt.y * sin_a,
                            y: center.y + pt.x * sin_a + pt.y * cos_a)
                }
                p.move(to: rotated[0])
                for i in 1..<rotated.count { p.addLine(to: rotated[i]) }
                p.closeSubpath()
            }
            context.fill(path, with: .color(stitchColor))

        case .french:
            // Narrow diamond (3:1 aspect)
            let long = screenSize / 2
            let short = screenSize / 6
            let angle = hole.angle
            let cos_a = cos(angle)
            let sin_a = sin(angle)
            let path = Path { p in
                p.move(to: CGPoint(x: center.x + long * cos_a, y: center.y + long * sin_a))
                p.addLine(to: CGPoint(x: center.x - short * sin_a, y: center.y + short * cos_a))
                p.addLine(to: CGPoint(x: center.x - long * cos_a, y: center.y - long * sin_a))
                p.addLine(to: CGPoint(x: center.x + short * sin_a, y: center.y - short * cos_a))
                p.closeSubpath()
            }
            context.fill(path, with: .color(stitchColor))
        }
    }

    private func drawText(_ text: TextShape, color: Color, in context: GraphicsContext) {
        var ctx = context
        if text.rotation != 0 {
            let centerScreen = transform.worldToScreen(text.unrotatedCenter)
            ctx.translateBy(x: centerScreen.x, y: centerScreen.y)
            ctx.rotate(by: .radians(text.rotation))
            ctx.translateBy(x: -centerScreen.x, y: -centerScreen.y)
        }
        let screenPos = transform.worldToScreen(text.position)
        let screenFontSize = transform.worldToScreenDistance(text.fontSize)
        let clampedSize = max(6, min(screenFontSize, 200))

        // Use NSFontManager-resolved font name to ensure bold/italic variants are applied
        let resolvedNSFont = text.resolvedNSFont
        let font = Font.custom(resolvedNSFont.fontName, size: clampedSize)

        // Split into lines and measure for alignment
        let lines = text.content.components(separatedBy: "\n")
        let nsFont = NSFont(name: resolvedNSFont.fontName, size: clampedSize)
            ?? NSFont.systemFont(ofSize: clampedSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: nsFont]

        // Find the widest line for alignment reference
        let lineWidths = lines.map { ($0 as NSString).size(withAttributes: attrs).width }
        let maxWidth = lineWidths.max() ?? 0
        let lineHeight = nsFont.ascender - nsFont.descender + nsFont.leading

        for (i, line) in lines.enumerated() {
            let lineWidth = lineWidths[i]
            let xOffset: CGFloat
            switch text.textAlignment {
            case .left: xOffset = 0
            case .center: xOffset = (maxWidth - lineWidth) / 2
            case .right: xOffset = maxWidth - lineWidth
            }

            let linePos = CGPoint(
                x: screenPos.x + xOffset,
                y: screenPos.y + CGFloat(i) * lineHeight
            )
            ctx.draw(
                Text(line)
                    .font(font)
                    .foregroundColor(color),
                at: linePos,
                anchor: .topLeading
            )
        }
    }

    // MARK: - Dimension Line Rendering

    private func drawDimension(_ dim: DimensionLineShape, in context: GraphicsContext) {
        let color = DesignTokens.dimensionColor(colorScheme)
        let style = SwiftUI.StrokeStyle(lineWidth: 1.0)

        let (a, b) = dim.dimEndpoints
        let sA = transform.worldToScreen(a)
        let sB = transform.worldToScreen(b)
        let sStart = transform.worldToScreen(dim.start)
        let sEnd = transform.worldToScreen(dim.end)

        // Extension lines: from each measured point to the dimension line, with a
        // small gap near the object and a slight overshoot past the line.
        let gap: CGFloat = 2
        let overshoot: CGFloat = 2
        for (from, to) in [(sStart, sA), (sEnd, sB)] {
            let d = unitVector(from: from, to: to)
            guard d != .zero else { continue }
            let p0 = CGPoint(x: from.x + d.x * gap, y: from.y + d.y * gap)
            let p1 = CGPoint(x: to.x + d.x * overshoot, y: to.y + d.y * overshoot)
            let path = Path { p in p.move(to: p0); p.addLine(to: p1) }
            context.stroke(path, with: .color(color), style: style)
        }

        // Dimension line
        let dimPath = Path { p in p.move(to: sA); p.addLine(to: sB) }
        context.stroke(dimPath, with: .color(color), style: style)

        // Arrowheads (world size, clamped so they stay visible on screen).
        let arrowLen = max(5, min(transform.worldToScreenDistance(DimensionLineShape.arrowLength), 14))
        let dir = unitVector(from: sA, to: sB)
        if dir != .zero {
            drawArrowhead(tip: sA, bodyDir: dir, length: arrowLen, color: color, in: context)
            drawArrowhead(tip: sB, bodyDir: CGPoint(x: -dir.x, y: -dir.y), length: arrowLen, color: color, in: context)
        }

        // Label: centered on the dimension line, nudged to the outward side.
        let label = dim.displayLabel(unit: unit)
        let fontSize = max(9, min(transform.worldToScreenDistance(DimensionLineShape.textHeight), 40))
        let midDim = transform.worldToScreen(dim.labelAnchor)
        let midMeasured = transform.worldToScreen(dim.start.midpoint(to: dim.end))
        var outward = unitVector(from: midMeasured, to: midDim)
        if outward == .zero { outward = CGPoint(x: 0, y: -1) }
        let labelPos = CGPoint(x: midDim.x + outward.x * (fontSize * 0.8),
                               y: midDim.y + outward.y * (fontSize * 0.8))
        context.draw(
            Text(label)
                .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                .foregroundColor(color),
            at: labelPos,
            anchor: .center
        )
    }

    private func drawArrowhead(tip: CGPoint, bodyDir: CGPoint, length: CGFloat, color: Color, in context: GraphicsContext) {
        let halfW = length * 0.35
        let base = CGPoint(x: tip.x + bodyDir.x * length, y: tip.y + bodyDir.y * length)
        let perp = CGPoint(x: -bodyDir.y, y: bodyDir.x)
        let p1 = CGPoint(x: base.x + perp.x * halfW, y: base.y + perp.y * halfW)
        let p2 = CGPoint(x: base.x - perp.x * halfW, y: base.y - perp.y * halfW)
        let path = Path { p in
            p.move(to: tip); p.addLine(to: p1); p.addLine(to: p2); p.closeSubpath()
        }
        context.fill(path, with: .color(color))
    }

    private func unitVector(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-9 else { return .zero }
        return CGPoint(x: dx / len, y: dy / len)
    }
}
