import SwiftUI

struct LayerListView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Layer actions bar
            HStack(spacing: 4) {
                Button(action: addLayer) {
                    Image(systemName: "plus").font(.system(size: 14))
                        .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
                }
                .buttonStyle(.plain)

                Button(action: removeLayer) {
                    Image(systemName: "trash").font(.system(size: 14))
                        .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
                }
                .buttonStyle(.plain)
                .disabled(editor.document.layers.count <= 1)

                Spacer()

                Button(action: moveLayerUp) {
                    Image(systemName: "chevron.up").font(.system(size: 14))
                        .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
                }
                .buttonStyle(.plain)

                Button(action: moveLayerDown) {
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
                            Button(action: { editor.document.layers[index].isVisible.toggle() }) {
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

    private func addLayer() {
        let newLayer = Layer(name: "Layer \(editor.document.layers.count + 1)")
        editor.document.layers.append(newLayer)
        editor.activeLayerIndex = editor.document.layers.count - 1
    }

    private func removeLayer() {
        guard editor.document.layers.count > 1 else { return }
        editor.document.layers.remove(at: editor.activeLayerIndex)
        editor.activeLayerIndex = min(editor.activeLayerIndex, editor.document.layers.count - 1)
    }

    private func moveLayerUp() {
        guard editor.activeLayerIndex > 0 else { return }
        editor.document.layers.swapAt(editor.activeLayerIndex, editor.activeLayerIndex - 1)
        editor.activeLayerIndex -= 1
    }

    private func moveLayerDown() {
        guard editor.activeLayerIndex < editor.document.layers.count - 1 else { return }
        editor.document.layers.swapAt(editor.activeLayerIndex, editor.activeLayerIndex + 1)
        editor.activeLayerIndex += 1
    }
}
