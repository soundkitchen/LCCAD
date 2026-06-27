import SwiftUI

/// Dialog for saving the current selection to the template library.
/// Lets the user name the template and choose whether it is stored flattened
/// (shapes kept separate) or wrapped in a single group.
struct SaveTemplateSheet: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String = ""
    /// false = 平坦 (flatten), true = グループ (single group).
    @State private var asGroup: Bool = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
            actionBar
        }
        .frame(width: 440, height: 248)
        .background(DesignTokens.bgPanel(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { nameFocused = true }
    }

    private var titleBar: some View {
        HStack {
            Spacer()
            Text("テンプレートを保存")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary(colorScheme))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .frame(height: 44)
        .background(DesignTokens.bgToolbar(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.border(colorScheme)).frame(height: 1)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("名前")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                TextField("テンプレート名", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($nameFocused)
                    .onSubmit(commit)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(DesignTokens.bgInput(colorScheme))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(nameFocused ? DesignTokens.accent : DesignTokens.border(colorScheme), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("保存形式")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                Picker("", selection: $asGroup) {
                    Text("平坦").tag(false)
                    Text("グループ").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("平坦＝図形のまま配置 / グループ＝1つにまとめて配置")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Text("キャンセル")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                    .padding(.horizontal, 16)
                    .frame(height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignTokens.border(colorScheme), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: commit) {
                Text("保存")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.textOnAccent)
                    .padding(.horizontal, 16)
                    .frame(height: 28)
                    .background(DesignTokens.accent)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .disabled(!editor.hasSelection)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignTokens.border(colorScheme)).frame(height: 1)
        }
    }

    private func commit() {
        guard editor.hasSelection else { return }
        editor.saveSelectionAsTemplate(name: name, asGroup: asGroup)
        dismiss()
    }
}
