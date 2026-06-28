import SwiftUI

/// Right-panel section shown while the Bevel tool is active. Sets the shared
/// `bevelRadius` used by both single-corner clicks and the bulk Bevel sheet.
struct BevelSection: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PropertySection(title: "Bevel") {
            HStack(spacing: 8) {
                Text("Radius")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                    .frame(width: 70, alignment: .leading)

                NumberBoxField(value: editor.bevelRadius, range: 0.1...100) {
                    editor.bevelRadius = $0
                }

                Text("mm")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))
            }

            Text("Click a corner to round it")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.textMuted(colorScheme))
        }
    }
}
