import SwiftUI

/// Horizontal ruler view drawn at the top of the canvas area.
struct HorizontalRulerView: View {
    let editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            RulerRenderer.drawHorizontalRuler(
                in: context,
                size: size,
                transform: editor.transform,
                unit: editor.document.settings.unit,
                mouseWorldX: editor.cursorWorldPosition.x,
                colorScheme: colorScheme
            )
        }
        .frame(height: DesignTokens.rulerHeight)
        .background(DesignTokens.bgToolbar(colorScheme))
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.border(colorScheme))
                .frame(height: 1)
        }
    }
}

/// Vertical ruler view drawn at the left of the canvas area.
struct VerticalRulerView: View {
    let editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            RulerRenderer.drawVerticalRuler(
                in: context,
                size: size,
                transform: editor.transform,
                unit: editor.document.settings.unit,
                mouseWorldY: editor.cursorWorldPosition.y,
                colorScheme: colorScheme
            )
        }
        .frame(width: DesignTokens.rulerHeight)
        .background(DesignTokens.bgToolbar(colorScheme))
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignTokens.border(colorScheme))
                .frame(width: 1)
        }
    }
}

/// The corner piece where horizontal and vertical rulers meet (top-left).
struct RulerCornerView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(DesignTokens.bgToolbar(colorScheme))
            .frame(width: DesignTokens.rulerHeight, height: DesignTokens.rulerHeight)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(DesignTokens.border(colorScheme))
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DesignTokens.border(colorScheme))
                    .frame(height: 1)
            }
    }
}
