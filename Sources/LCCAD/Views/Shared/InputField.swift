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
            if !isEditing { editText = formatted(newValue) }
        }
    }

    private func formatted(_ v: CGFloat) -> String {
        String(format: "%.1f", v)
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

/// Box-only editable numeric field (no built-in label or suffix). The caller
/// places the label and unit alongside it — used where the label sits outside
/// the input box (Bevel radius), unlike `EditablePropertyField`.
struct NumberBoxField: View {
    let value: CGFloat
    var range: ClosedRange<CGFloat>? = nil
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
        String(format: "%.1f", v)
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
