import SwiftUI

struct GridRenderer {
    let settings: ProjectSettings
    let transform: CanvasTransform
    let colorScheme: ColorScheme

    /// Minimum screen-pixel spacing for the finest visible grid tier.
    /// Below this, the tier is bumped up to the next coarser level.
    private static let minScreenSpacing: CGFloat = 8

    /// Screen-pixel range over which minor lines fade in (from 0 to full opacity).
    /// At minScreenSpacing the minor lines are invisible; at minScreenSpacing + fadeRange they are fully opaque.
    private static let fadeRange: CGFloat = 16

    /// The 1-2-5 series: ..., 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, ...
    /// Each group of 3 consecutive entries spans one decade (×10).
    private static let tiers: [CGFloat] = {
        var result: [CGFloat] = []
        for exp in -2...4 {
            let base = pow(10, CGFloat(exp))
            result.append(contentsOf: [base, base * 2, base * 5])
        }
        return result.sorted()
    }()

    func draw(in context: GraphicsContext, size: CGSize) {
        guard settings.showGrid else { return }

        let (fineSpacing, coarseSpacing) = adaptiveSpacings()

        // Minor line fade: smoothly transition from invisible to full opacity
        let fineScreenPx = transform.worldToScreenDistance(fineSpacing)
        let fadeAlpha = min(1.0, max(0.0, (fineScreenPx - GridRenderer.minScreenSpacing) / GridRenderer.fadeRange))

        // Draw major (coarse) grid — always full opacity
        if coarseSpacing > 0 {
            drawGridLines(
                spacing: coarseSpacing,
                size: size,
                color: DesignTokens.gridLineMajor(colorScheme),
                lineWidth: 1.0,
                in: context
            )
        }

        // Draw minor (fine) grid — with fade
        if fadeAlpha > 0.01 {
            drawGridLines(
                spacing: fineSpacing,
                size: size,
                color: DesignTokens.gridLine(colorScheme).opacity(fadeAlpha),
                lineWidth: 0.5,
                in: context,
                skipMultiplesOf: coarseSpacing
            )
        }

        // Draw origin crosshair
        drawOrigin(size: size, in: context)
    }

    // MARK: - Adaptive Spacing

    /// Returns (fineSpacing, coarseSpacing) in world units (mm).
    /// The relationship is always coarse = fine × 10 (3 tiers up in the 1-2-5 series).
    /// This guarantees a consistent 10-subdivision pattern at every zoom level.
    func adaptiveSpacings() -> (fine: CGFloat, coarse: CGFloat) {
        let tiers = GridRenderer.tiers

        // Find the finest tier whose screen spacing >= minScreenSpacing
        var fineIndex = tiers.count - 1
        for (i, tier) in tiers.enumerated() {
            let screenPx = transform.worldToScreenDistance(tier)
            if screenPx >= GridRenderer.minScreenSpacing {
                fineIndex = i
                break
            }
        }

        let fineSpacing = tiers[fineIndex]

        // Coarse = 3 tiers up (one decade in the 1-2-5 series = ×10)
        let coarseIndex = min(fineIndex + 3, tiers.count - 1)
        let coarseSpacing = fineIndex + 3 < tiers.count ? tiers[coarseIndex] : 0

        return (fineSpacing, coarseSpacing)
    }

    // MARK: - Drawing

    private func drawGridLines(
        spacing: CGFloat,
        size: CGSize,
        color: Color,
        lineWidth: CGFloat,
        in context: GraphicsContext,
        skipMultiplesOf skipSpacing: CGFloat = 0
    ) {
        let topLeft = transform.screenToWorld(CGPoint(x: 0, y: 0))
        let bottomRight = transform.screenToWorld(CGPoint(x: size.width, y: size.height))

        let startX = floor(topLeft.x / spacing) * spacing
        let endX = ceil(bottomRight.x / spacing) * spacing
        let startY = floor(topLeft.y / spacing) * spacing
        let endY = ceil(bottomRight.y / spacing) * spacing

        // Vertical lines
        var x = startX
        while x <= endX {
            if skipSpacing > 0 {
                let ratio = x / skipSpacing
                if abs(ratio - ratio.rounded()) < 0.01 {
                    x += spacing
                    continue
                }
            }
            let screenX = transform.worldToScreen(CGPoint(x: x, y: 0)).x
            let path = Path { p in
                p.move(to: CGPoint(x: screenX, y: 0))
                p.addLine(to: CGPoint(x: screenX, y: size.height))
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
            x += spacing
        }

        // Horizontal lines
        var y = startY
        while y <= endY {
            if skipSpacing > 0 {
                let ratio = y / skipSpacing
                if abs(ratio - ratio.rounded()) < 0.01 {
                    y += spacing
                    continue
                }
            }
            let screenY = transform.worldToScreen(CGPoint(x: 0, y: y)).y
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: screenY))
                p.addLine(to: CGPoint(x: size.width, y: screenY))
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
            y += spacing
        }
    }

    private func drawOrigin(size: CGSize, in context: GraphicsContext) {
        let originScreen = transform.worldToScreen(CGPoint.zero)
        let originColor = Color.red.opacity(0.35)

        if originScreen.x >= 0 && originScreen.x <= size.width {
            let path = Path { p in
                p.move(to: CGPoint(x: originScreen.x, y: 0))
                p.addLine(to: CGPoint(x: originScreen.x, y: size.height))
            }
            context.stroke(path, with: .color(originColor), lineWidth: 0.75)
        }
        if originScreen.y >= 0 && originScreen.y <= size.height {
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: originScreen.y))
                p.addLine(to: CGPoint(x: size.width, y: originScreen.y))
            }
            context.stroke(path, with: .color(originColor), lineWidth: 0.75)
        }
    }
}
