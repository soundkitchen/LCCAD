import SwiftUI

struct LayerListView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Layer actions bar
            HStack(spacing: 4) {
                Button(action: editor.addLayer) {
                    Image(systemName: "plus").font(.system(size: 14))
                        .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
                }
                .buttonStyle(.plain)

                Button(action: editor.removeActiveLayer) {
                    Image(systemName: "trash").font(.system(size: 14))
                        .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
                }
                .buttonStyle(.plain)
                .disabled(editor.document.layers.count <= 1)

                Spacer()

                Button(action: editor.moveActiveLayerUp) {
                    Image(systemName: "chevron.up").font(.system(size: 14))
                        .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
                }
                .buttonStyle(.plain)

                Button(action: editor.moveActiveLayerDown) {
                    Image(systemName: "chevron.down").font(.system(size: 14))
                        .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DesignTokens.borderLight(colorScheme)).frame(height: 1)
            }

            // Layer list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(editor.document.layers.enumerated()), id: \.element.id) { index, layer in
                        HStack(spacing: 8) {
                            Button(action: { editor.toggleLayerVisibility(at: index) }) {
                                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                                    .font(.system(size: 14))
                                    .foregroundStyle(layer.isVisible ? DesignTokens.iconPrimary(colorScheme) : DesignTokens.textMuted(colorScheme))
                            }
                            .buttonStyle(.plain)

                            Text(layer.name)
                                .font(.system(size: 11))
                                .foregroundStyle(layer.isVisible ? DesignTokens.textPrimary(colorScheme) : DesignTokens.textMuted(colorScheme))

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(index == editor.activeLayerIndex ? DesignTokens.bgToolActive(colorScheme) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editor.activeLayerIndex = index
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
