import SwiftUI
import AppKit

struct StrokeSection: View {
    @Bindable var editor: EditorViewModel
    let stroke: StrokeStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PropertySection(title: "Stroke") {
            HStack(spacing: 8) {
                // ドラッグ中は連続で呼ばれるため、1 回のドラッグ / クリックを 1 件の Undo にまとめる (#72)
                CodableColorPicker(
                    color: stroke.color,
                    currentColors: { editor.selectedShapes.map(\.stroke.color) }
                ) { newColor in
                    editor.updateStroke(coalescing: .strokeColor) { $0.color = newColor }
                }

                // Width is fixed app-wide (StrokeStyle.fixedWidth) so printed
                // line thickness never shifts calibrated dimensions.
                Text(verbatim: "\(StrokeStyle.fixedWidth) mm (fixed)")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))
            }

            HStack(spacing: 8) {
                Text("Style")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))

                Menu {
                    ForEach(LineStyle.allCases, id: \.self) { style in
                        Button {
                            editor.updateStroke {
                                $0.lineStyle = style
                                $0.dashPattern = style.dashPattern
                            }
                        } label: {
                            Text(style.displayName)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        LineStylePreview(
                            style: stroke.lineStyle,
                            color: DesignTokens.textPrimary(colorScheme)
                        )
                        .frame(width: 30, height: 12)

                        Text(stroke.lineStyle.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textPrimary(colorScheme))

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignTokens.textMuted(colorScheme))
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(DesignTokens.bgInput(colorScheme))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignTokens.border(colorScheme), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
    }
}
