import SwiftUI

struct LayerListView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    /// 名前を編集中のレイヤー(#95)。確定・取り消しで nil に戻す
    @State private var editingLayerId: UUID?
    /// 編集中の名前(未確定文字を含む)。確定するまで document には書き込まない。
    /// 欄が確定を伝える前に編集を終えるとき(別のレイヤーの編集に移る、リストが消える)に使う
    @State private var draftName = ""

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

                            if editingLayerId == layer.id {
                                nameField(for: layer)
                            } else {
                                Text(layer.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(layer.isVisible ? DesignTokens.textPrimary(colorScheme) : DesignTokens.textMuted(colorScheme))

                                Spacer()
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(index == editor.activeLayerIndex ? DesignTokens.bgToolActive(colorScheme) : Color.clear)
                        .contentShape(Rectangle())
                        // ダブルクリックで名前を編集する。1 回目のクリックでアクティブレイヤーを
                        // 切り替えるのは待たずに行う(onTapGesture を 2 つ重ねると、シングルクリックが
                        // ダブルクリックの判定を待って遅れるため、シングルは simultaneousGesture にする)
                        .onTapGesture(count: 2) {
                            startRenaming(layer)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            editor.activeLayerIndex = index
                        })
                        .contextMenu {
                            Button("Rename") {
                                startRenaming(layer)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onChange(of: editor.document.layers.map(\.id)) { _, ids in
            // 編集中のレイヤーが Undo などで消えたら、編集をやめる(review #97)。
            // 残しておくと、Redo で同じ id のレイヤーが戻ったときに古い下書きのまま編集が続く
            if let editingLayerId, !ids.contains(editingLayerId) { cancelRenaming() }
        }
        .onDisappear {
            // Templates タブへの切り替えなどでリストが消えたら、編集中の名前を確定する
            commitRenaming(draftName)
        }
    }

    /// 名前の編集欄。Enter・欄の外のクリック・フォーカスが外れたときに確定し、Escape で取り消す。
    /// 入力の Undo は欄の中だけで扱う(`LayerNameField` 参照)
    private func nameField(for layer: Layer) -> some View {
        LayerNameField(
            initialName: layer.name,
            onChange: { draftName = $0 },
            focusAfterEditing: { editor.canvasKeyView },
            onCommit: { name in
                // 別のレイヤーの編集に移った後に、古い欄から届いた確定は無視する
                guard editingLayerId == layer.id else { return }
                commitRenaming(name)
            },
            onCancel: {
                guard editingLayerId == layer.id else { return }
                cancelRenaming()
            }
        )
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background(DesignTokens.bgInput(colorScheme))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(DesignTokens.accent, lineWidth: 1)
        )
    }

    private func startRenaming(_ layer: Layer) {
        // 同じレイヤーの編集中(欄の中のダブルクリックなど)は、入力中の名前を残す
        guard editingLayerId != layer.id else { return }
        commitRenaming(draftName)
        draftName = layer.name
        editingLayerId = layer.id
    }

    /// 編集中の名前を確定する。先に編集状態を解くので、2 回目以降は何もしない
    private func commitRenaming(_ name: String) {
        guard let id = editingLayerId else { return }
        editingLayerId = nil
        guard let index = editor.document.layers.firstIndex(where: { $0.id == id }) else { return }
        // 空になる名前は無視して元の名前のままにする(renameLayer が投げて何も変えない)
        try? editor.renameLayer(at: index, to: name)
    }

    private func cancelRenaming() {
        editingLayerId = nil
    }
}
