import SwiftUI

struct PropertySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .textCase(.uppercase)
                .tracking(0.5)

            content
        }
        .padding(12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.borderLight(colorScheme)).frame(height: 1)
        }
    }
}

struct PropertyField: View {
    let label: String
    let value: CGFloat
    var suffix: String = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textMuted(colorScheme))
                .frame(width: 14)

            Text(formattedValue)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textPrimary(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DesignTokens.bgInput(colorScheme))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(DesignTokens.border(colorScheme), lineWidth: 1)
        )
    }

    private var formattedValue: String {
        let v = String(format: "%.1f", value)
        return suffix.isEmpty ? v : "\(v) \(suffix)"
    }
}

/// Editable numeric field with Enter/focus-out commit and invalid-input rollback.
/// Re-usable for Position, Zoom, Stroke-width, etc.
struct EditablePropertyField: View {
    let label: String
    let value: CGFloat
    var suffix: String = ""
    var range: ClosedRange<CGFloat>? = nil
    var onCommit: (CGFloat) -> Void

    @State private var editText: String = ""
    /// 編集開始(フォーカス取得)時点の表示文字列。無編集のままの確定を
    /// 検出するための基準 (#55)。
    @State private var textAtEditStart: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textMuted(colorScheme))
                .frame(width: 14)

            TextField("", text: $editText)
                .font(.system(size: 11))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { commitEdit() }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        isEditing = true
                        textAtEditStart = editText
                    } else {
                        commitEdit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DesignTokens.bgInput(colorScheme))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? DesignTokens.accent : DesignTokens.border(colorScheme), lineWidth: 1)
        )
        .onAppear { editText = formatted(value) }
        .onChange(of: value) { _, newValue in
            if !isEditing {
                editText = formatted(newValue)
                // Enter 確定後の正規化(例: Arc 角度 370°→10°)でフォーカス保持の
                // まま表示が再同期されるケースで、続くフォーカスアウトが文字列
                // 不一致となり再コミットされるのを防ぐ(レビュー #57 指摘)
                textAtEditStart = editText
            }
        }
    }

    private func formatted(_ v: CGFloat) -> String {
        String(format: "%.1f", v)
    }

    /// 確定時にコミットすべき値を判定する(テストのため切り出し)。
    /// nil はコミットしない: 表示文字列が編集開始時から変わっていない
    /// (無編集フォーカスアウト)か、数値としてパースできない場合。
    /// 無編集ガードがないと %.1f 丸め表示がそのまま書き戻され、実値が
    /// 無言で変化し no-op の Undo も積まれてしまう (#55)。
    static func valueToCommit(editText: String, textAtEditStart: String, range: ClosedRange<CGFloat>?) -> CGFloat? {
        guard editText != textAtEditStart else { return nil }
        guard let parsed = Double(editText) else { return nil }
        var clamped = CGFloat(parsed)
        if let range {
            clamped = min(max(clamped, range.lowerBound), range.upperBound)
        }
        return clamped
    }

    private func commitEdit() {
        isEditing = false
        guard let newValue = Self.valueToCommit(editText: editText, textAtEditStart: textAtEditStart, range: range) else {
            // 値が外部から変わっていた場合に備えて表示を現在値へ再同期。
            // 基準文字列も合わせ、続くフォーカスアウトでの再コミットを防ぐ
            editText = formatted(value)
            textAtEditStart = editText
            return
        }
        onCommit(newValue)
        editText = formatted(newValue)
        // Enter 確定後にフォーカスアウトで commitEdit が再度呼ばれても
        // 二重コミットにならないよう、基準文字列を確定後の表示に合わせる
        textAtEditStart = editText
    }
}

/// Box-only editable numeric field (no built-in label or suffix). The caller
/// places the label and unit alongside it — used where the label sits outside
/// the input box (Bevel radius), unlike `EditablePropertyField`.
struct NumberBoxField: View {
    let value: CGFloat
    var range: ClosedRange<CGFloat>? = nil
    /// Decimal places shown when not editing (0 for integer fields like hole count).
    var fractionDigits: Int = 1
    var onCommit: (CGFloat) -> Void

    @State private var editText: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TextField("", text: $editText)
            .font(.system(size: 11))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit { commitEdit() }
            .onChange(of: isFocused) { _, focused in
                if focused { isEditing = true } else { commitEdit() }
            }
            .onChange(of: editText) { _, newText in
                // Live-commit: push every parseable value to the binding right away
                // so an Apply button (e.g. the Bevel sheet) never reads a stale value
                // while the field still has focus.
                guard isEditing, let parsed = Double(newText) else { return }
                var next = CGFloat(parsed)
                if let range { next = min(max(next, range.lowerBound), range.upperBound) }
                if next != value { onCommit(next) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(DesignTokens.bgInput(colorScheme))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isFocused ? DesignTokens.accent : DesignTokens.border(colorScheme), lineWidth: 1)
            )
            .onAppear { editText = formatted(value) }
            .onChange(of: value) { _, newValue in
                if !isEditing { editText = formatted(newValue) }
            }
    }

    private func formatted(_ v: CGFloat) -> String {
        String(format: "%.\(fractionDigits)f", v)
    }

    private func commitEdit() {
        isEditing = false
        guard let parsed = Double(editText) else {
            editText = formatted(value)
            return
        }
        var clamped = CGFloat(parsed)
        if let range {
            clamped = min(max(clamped, range.lowerBound), range.upperBound)
        }
        onCommit(clamped)
        editText = formatted(clamped)
    }
}
