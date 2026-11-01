import AppKit
import SwiftUI

struct LayerListView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    /// 名前を編集中のレイヤー(#95)。確定・取り消しで nil に戻す
    @State private var editingLayerId: UUID?
    /// 編集中の名前。確定するまで document には書き込まない
    @State private var draftName = ""
    /// 名前の編集欄にフォーカスがあるレイヤー。欄ごとに区別して、別のレイヤーの編集に
    /// 移ったときの古い欄のフォーカスアウトで、新しい欄の編集を確定しないようにする
    @FocusState private var focusedNameFieldId: UUID?
    /// 編集中だけ置く、入力欄の外のマウスダウンを拾うローカルモニター
    @State private var outsideClickMonitor: Any?

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
                                nameField(for: layer.id)
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
        .onChange(of: focusedNameFieldId) { oldId, newId in
            // ほかの場所をクリックするなどで、編集中の欄からフォーカスが外れたら確定する
            if let oldId, oldId == editingLayerId, newId != oldId { commitRenaming() }
        }
        // 欄の外のクリックを拾うモニターは、編集中だけ置く
        .onChange(of: editingLayerId) { _, id in
            if id == nil { removeOutsideClickMonitor() } else { installOutsideClickMonitor() }
        }
        .onDisappear {
            // Templates タブへの切り替えなどでリストが消えたら、編集中の名前を確定する
            commitRenaming()
            removeOutsideClickMonitor()
        }
    }

    /// 名前の編集欄。Enter・フォーカスが外れたとき・欄の外のクリックで確定し、Escape で取り消す
    private func nameField(for layerId: UUID) -> some View {
        TextField("", text: $draftName)
            .font(.system(size: 11))
            .textFieldStyle(.plain)
            .focused($focusedNameFieldId, equals: layerId)
            .onSubmit { commitRenaming() }
            .onExitCommand { cancelRenaming() }
            .padding(.horizontal, 4)
            .frame(height: 22)
            .background(DesignTokens.bgInput(colorScheme))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(DesignTokens.accent, lineWidth: 1)
            )
            .onAppear {
                // 右クリックメニューから始めたときは、メニューが閉じてからでないと
                // フォーカスが移らないことがあるので、次のループで移す
                DispatchQueue.main.async { focusedNameFieldId = layerId }
            }
    }

    /// パネルの空きスペースや Properties の余白など、フォーカスを取らない場所をクリックしても
    /// 入力欄はフォーカスを手放さない(macOS の挙動)。そのため、欄の外のマウスダウンを
    /// ローカルモニターで拾って確定する。イベントは消費しないので、クリックした先の操作は
    /// そのまま行われる
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            // ローカルモニターはメインスレッドで呼ばれる
            MainActor.assumeIsolated {
                if !Self.isInFocusedTextField(event) { commitRenaming() }
            }
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// マウスダウンが、イベントのウィンドウで編集中のテキスト欄(フィールドエディタ)の上か
    @MainActor
    private static func isInFocusedTextField(_ event: NSEvent) -> Bool {
        guard let window = event.window,
              let fieldEditor = window.firstResponder as? NSTextView,
              let contentView = window.contentView else { return false }
        let point = contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        guard let hit = contentView.hitTest(point) else { return false }
        if hit === fieldEditor || hit.isDescendant(of: fieldEditor) { return true }
        // 欄の内側の余白はフィールドエディタではなく NSTextField 自身に当たる
        return (hit as? NSTextField)?.currentEditor() === fieldEditor
    }

    private func startRenaming(_ layer: Layer) {
        // 同じレイヤーの編集中(欄の中のダブルクリックなど)は、入力中の名前を残す
        guard editingLayerId != layer.id else { return }
        commitRenaming()
        draftName = layer.name
        editingLayerId = layer.id
    }

    /// 編集中の名前を確定する。先に編集状態を解くので、確定の後に続くフォーカスアウトでは何もしない。
    /// 空白だけの名前は `renameLayer` が無視する(元の名前のまま)
    private func commitRenaming() {
        guard let id = editingLayerId else { return }
        editingLayerId = nil
        guard let index = editor.document.layers.firstIndex(where: { $0.id == id }) else { return }
        editor.renameLayer(at: index, to: draftName)
    }

    private func cancelRenaming() {
        editingLayerId = nil
    }
}
