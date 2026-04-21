import SwiftUI

/// Core Graphics-based ruler drawing logic.
/// Draws tick marks and labels based on the current zoom level using the same
/// adaptive 1-2-5 spacing series as GridRenderer.
struct RulerRenderer {
    /// The 1-2-5 series tiers (matching GridRenderer)
    private static let tiers: [CGFloat] = {
        var result: [CGFloat] = []
        for exp in -2...4 {
            let base = pow(10, CGFloat(exp))
            result.append(contentsOf: [base, base * 2, base * 5])
        }
        return result.sorted()
    }()

    /// Minimum screen-pixel spacing for the finest visible tick tier.
    private static let minScreenSpacing: CGFloat = 8

    /// Calculate adaptive spacings for ruler ticks — same logic as GridRenderer.
    static func adaptiveSpacings(scale: CGFloat) -> (fine: CGFloat, coarse: CGFloat) {
        var fineIndex = tiers.count - 1
        for (i, tier) in tiers.enumerated() {
            let screenPx = tier * scale
            if screenPx >= minScreenSpacing {
                fineIndex = i
                break
            }
        }

        let fineSpacing = tiers[fineIndex]
        let coarseIndex = min(fineIndex + 3, tiers.count - 1)
        let coarseSpacing = fineIndex + 3 < tiers.count ? tiers[coarseIndex] : fineSpacing * 10

        return (fineSpacing, coarseSpacing)
    }

    // MARK: - Horizontal Ruler

    static func drawHorizontalRuler(
        in context: GraphicsContext,
        size: CGSize,
        transform: CanvasTransform,
        unit: LengthUnit,
        mouseWorldX: CGFloat?,
        colorScheme: ColorScheme
    ) {
        let rulerHeight = DesignTokens.rulerHeight
        let tickColor = DesignTokens.textSecondary(colorScheme)

        let (fineSpacing, coarseSpacing) = adaptiveSpacings(scale: transform.scale)

        // Determine visible world range
        let leftWorld = transform.screenToWorld(CGPoint(x: 0, y: 0)).x
        let rightWorld = transform.screenToWorld(CGPoint(x: size.width, y: 0)).x

        // Draw fine ticks
        let startX = floor(leftWorld / fineSpacing) * fineSpacing
        let endX = ceil(rightWorld / fineSpacing) * fineSpacing
        var x = startX
        while x <= endX {
            let screenX = transform.worldToScreen(CGPoint(x: x, y: 0)).x
            let isCoarse = isMultiple(x, of: coarseSpacing)
            let tickHeight: CGFloat = isCoarse ? rulerHeight * 2.0 / 3.0 : rulerHeight / 3.0

            let path = Path { p in
                p.move(to: CGPoint(x: screenX, y: rulerHeight))
                p.addLine(to: CGPoint(x: screenX, y: rulerHeight - tickHeight))
            }
            context.stroke(path, with: .color(tickColor), lineWidth: 0.5)

            // Draw label for coarse ticks
            if isCoarse {
                let label = formatLabel(value: x, unit: unit)
                let text = Text(label)
                    .font(.custom("Geist Mono", size: 9))
                    .foregroundColor(tickColor)
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: screenX + 2, y: 2),
                    anchor: .topLeading
                )
            }

            x += fineSpacing
        }

        // Draw mouse indicator
        if let mouseX = mouseWorldX {
            let screenX = transform.worldToScreen(CGPoint(x: mouseX, y: 0)).x
            let indicatorPath = Path { p in
                p.move(to: CGPoint(x: screenX, y: 0))
                p.addLine(to: CGPoint(x: screenX, y: rulerHeight))
            }
            context.stroke(indicatorPath, with: .color(DesignTokens.rulerIndicatorColor), lineWidth: 1)
        }
    }

    // MARK: - Vertical Ruler

    static func drawVerticalRuler(
        in context: GraphicsContext,
        size: CGSize,
        transform: CanvasTransform,
        unit: LengthUnit,
        mouseWorldY: CGFloat?,
        colorScheme: ColorScheme
    ) {
        let rulerWidth = DesignTokens.rulerHeight  // same 24px
        let tickColor = DesignTokens.textSecondary(colorScheme)

        let (fineSpacing, coarseSpacing) = adaptiveSpacings(scale: transform.scale)

        // Determine visible world range
        let topWorld = transform.screenToWorld(CGPoint(x: 0, y: 0)).y
        let bottomWorld = transform.screenToWorld(CGPoint(x: 0, y: size.height)).y

        // Draw fine ticks
        let startY = floor(topWorld / fineSpacing) * fineSpacing
        let endY = ceil(bottomWorld / fineSpacing) * fineSpacing
        var y = startY
        while y <= endY {
            let screenY = transform.worldToScreen(CGPoint(x: 0, y: y)).y
            let isCoarse = isMultiple(y, of: coarseSpacing)
            let tickWidth: CGFloat = isCoarse ? rulerWidth * 2.0 / 3.0 : rulerWidth / 3.0

            let path = Path { p in
                p.move(to: CGPoint(x: rulerWidth, y: screenY))
                p.addLine(to: CGPoint(x: rulerWidth - tickWidth, y: screenY))
            }
            context.stroke(path, with: .color(tickColor), lineWidth: 0.5)

            // Draw label for coarse ticks (rotated for vertical ruler)
            if isCoarse {
                let label = formatLabel(value: y, unit: unit)
                let text = Text(label)
                    .font(.custom("Geist Mono", size: 9))
                    .foregroundColor(tickColor)
                var labelContext = context
                labelContext.translateBy(x: 3, y: screenY + 3)
                labelContext.rotate(by: .degrees(-90))
                labelContext.draw(
                    context.resolve(text),
                    at: CGPoint(x: 0, y: 0),
                    anchor: .bottomLeading
                )
            }

            y += fineSpacing
        }

        // Draw mouse indicator
        if let mouseY = mouseWorldY {
            let screenY = transform.worldToScreen(CGPoint(x: 0, y: mouseY)).y
            let indicatorPath = Path { p in
                p.move(to: CGPoint(x: 0, y: screenY))
                p.addLine(to: CGPoint(x: rulerWidth, y: screenY))
            }
            context.stroke(indicatorPath, with: .color(DesignTokens.rulerIndicatorColor), lineWidth: 1)
        }
    }

    // MARK: - Helpers

    private static func isMultiple(_ value: CGFloat, of spacing: CGFloat) -> Bool {
        guard spacing > 0 else { return false }
        let ratio = value / spacing
        return abs(ratio - ratio.rounded()) < 0.01
    }

    private static func formatLabel(value: CGFloat, unit: LengthUnit) -> String {
        let displayValue: CGFloat
        switch unit {
        case .millimeters:
            displayValue = value
        case .inches:
            displayValue = value / 25.4
        }

        // Format: show integer if close enough, otherwise 1 decimal
        if abs(displayValue - displayValue.rounded()) < 0.01 {
            return "\(Int(displayValue.rounded()))"
        } else {
            return String(format: "%.1f", displayValue)
        }
    }
}
