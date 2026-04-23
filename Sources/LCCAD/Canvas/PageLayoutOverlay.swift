import SwiftUI

/// Draws page frame overlays on the canvas.
enum PageLayoutOverlay {
    static func draw(
        layout: PageLayoutSettings,
        selectedPageId: UUID?,
        transform: CanvasTransform,
        colorScheme: ColorScheme,
        in context: GraphicsContext
    ) {
        let pages = layout.pages
        guard !pages.isEmpty else { return }

        let frameColor = DesignTokens.pageFrame(colorScheme)
        let selectedColor = DesignTokens.pageFrameSelected(colorScheme)
        let printableColor = DesignTokens.pagePrintableArea(colorScheme)
        let overlapColor = DesignTokens.pageOverlap(colorScheme)
        let numberColor = DesignTokens.pageNumber(colorScheme)

        // Draw overlap zones between adjacent pages
        for i in 0..<pages.count {
            for j in (i + 1)..<pages.count {
                let frameI = layout.pageFrame(for: pages[i])
                let frameJ = layout.pageFrame(for: pages[j])
                let intersection = frameI.intersection(frameJ)
                if !intersection.isNull && intersection.width > 0 && intersection.height > 0 {
                    let screenRect = transform.worldToScreen(intersection)
                    context.fill(Path(screenRect), with: .color(overlapColor))
                }
            }
        }

        // Draw each page frame
        for (index, page) in pages.enumerated() {
            let isSelected = page.id == selectedPageId
            let color = isSelected ? selectedColor : frameColor
            let lineWidth: CGFloat = isSelected ? 2 : 1

            let frame = layout.pageFrame(for: page)
            let printable = layout.pagePrintableArea(for: page)

            // Page frame outline
            let screenFrame = transform.worldToScreen(frame)
            let framePath = Path(screenFrame)
            context.stroke(framePath, with: .color(color),
                          style: SwiftUI.StrokeStyle(lineWidth: lineWidth, dash: [8, 4]))

            // Printable area (margin inset)
            let screenPrintable = transform.worldToScreen(printable)
            let printablePath = Path(screenPrintable)
            context.stroke(printablePath, with: .color(printableColor),
                          style: SwiftUI.StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

            // Page number label
            let label = Text("\(index + 1)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(numberColor)
            context.draw(label, at: CGPoint(x: screenFrame.minX + 12, y: screenFrame.minY + 14),
                        anchor: .topLeading)

            // Corner handles for selected page
            if isSelected {
                let handleSize: CGFloat = 8
                let corners = [
                    CGPoint(x: screenFrame.minX, y: screenFrame.minY),
                    CGPoint(x: screenFrame.maxX, y: screenFrame.minY),
                    CGPoint(x: screenFrame.minX, y: screenFrame.maxY),
                    CGPoint(x: screenFrame.maxX, y: screenFrame.maxY),
                ]
                for corner in corners {
                    let handleRect = CGRect(
                        x: corner.x - handleSize / 2,
                        y: corner.y - handleSize / 2,
                        width: handleSize,
                        height: handleSize
                    )
                    context.fill(Path(handleRect), with: .color(selectedColor))
                    context.stroke(Path(handleRect), with: .color(.white), lineWidth: 1)
                }
            }
        }
    }
}
