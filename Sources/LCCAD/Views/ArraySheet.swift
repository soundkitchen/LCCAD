import SwiftUI

struct ArraySheet: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var params: EditorViewModel.ArrayParameters = .default

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
            actionBar
        }
        .frame(width: 440, height: sheetHeight)
        .background(DesignTokens.bgPanel(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var titleBar: some View {
        HStack {
            Spacer()
            Text("Array")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary(colorScheme))
            Spacer()
            Button {
                dismiss()
            } label: {
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
        VStack(alignment: .leading, spacing: 14) {
            modePicker

            switch params.mode {
            case .linear:
                sectionHeader("LINEAR", active: true)
                linearForm
            case .grid:
                sectionHeader("GRID", active: true)
                gridForm
            case .polar:
                sectionHeader("POLAR", active: true)
                polarForm
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
    }

    /// Sized to fit the tallest form (Polar) so the sheet doesn't jump
    /// dimensions when the user switches modes mid-edit.
    private var sheetHeight: CGFloat {
        switch params.mode {
        case .linear: return 340
        case .grid:   return 380
        case .polar:  return 410
        }
    }

    private var modePicker: some View {
        Picker("", selection: $params.mode) {
            Text("Linear").tag(EditorViewModel.ArrayParameters.Mode.linear)
            Text("Grid").tag(EditorViewModel.ArrayParameters.Mode.grid)
            Text("Polar").tag(EditorViewModel.ArrayParameters.Mode.polar)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func sectionHeader(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(DesignTokens.textMuted(colorScheme))
            .opacity(active ? 1.0 : 0.5)
    }

    private var linearForm: some View {
        VStack(spacing: 8) {
            row(label: "Count") {
                intField(value: params.count, range: 2...500) { params.count = $0 }
            }
            row(label: "Offset X") {
                floatField(value: params.offsetX, suffix: "mm") { params.offsetX = $0 }
            }
            row(label: "Offset Y") {
                floatField(value: params.offsetY, suffix: "mm") { params.offsetY = $0 }
            }
        }
    }

    private var gridForm: some View {
        VStack(spacing: 8) {
            row(label: "Rows") {
                intField(value: params.rows, range: 1...100) { params.rows = $0 }
            }
            row(label: "Columns") {
                intField(value: params.cols, range: 1...100) { params.cols = $0 }
            }
            row(label: "Row Spacing") {
                floatField(value: params.rowSpacing, suffix: "mm") { params.rowSpacing = $0 }
            }
            row(label: "Col Spacing") {
                floatField(value: params.colSpacing, suffix: "mm") { params.colSpacing = $0 }
            }
        }
    }

    private var polarForm: some View {
        VStack(spacing: 8) {
            row(label: "Count") {
                intField(value: params.polarCount, range: 2...100) { params.polarCount = $0 }
            }
            row(label: "Radius") {
                floatField(value: params.polarRadius, suffix: "mm") { params.polarRadius = $0 }
            }
            row(label: "Start Angle") {
                floatField(value: params.polarStartAngle, suffix: "°") { params.polarStartAngle = $0 }
            }
            row(label: "Sweep") {
                floatField(value: params.polarSweepAngle, suffix: "°") { params.polarSweepAngle = $0 }
            }
            row(label: "Rotate Items") {
                Toggle("", isOn: $params.polarRotateItems)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }

    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .frame(width: 80, alignment: .leading)
            content()
        }
        .frame(height: 28)
    }

    private func intField(value: Int, range: ClosedRange<Int>, onCommit: @escaping (Int) -> Void) -> some View {
        IntInputField(value: value, range: range, onCommit: onCommit)
    }

    private func floatField(value: CGFloat, suffix: String, onCommit: @escaping (CGFloat) -> Void) -> some View {
        FloatInputField(value: value, suffix: suffix, onCommit: onCommit)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
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

            Button {
                editor.arraySelectedShapes(params)
                dismiss()
            } label: {
                Text("Apply")
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
}

// MARK: - Input Fields

private struct IntInputField: View {
    let value: Int
    let range: ClosedRange<Int>
    let onCommit: (Int) -> Void

    @State private var editText: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $editText)
                .font(.system(size: 11))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        isEditing = true
                    } else {
                        commit()
                    }
                }
                .onChange(of: editText) { _, newText in
                    // Live-commit: as long as the text parses to a number we
                    // push it to the binding immediately so Apply doesn't read
                    // stale values when the field still has focus.
                    guard isEditing else { return }
                    if let parsed = Int(newText) {
                        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
                        if clamped != value { onCommit(clamped) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(DesignTokens.bgInput(colorScheme))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? DesignTokens.accent : DesignTokens.border(colorScheme), lineWidth: 1)
        )
        .onAppear { editText = String(value) }
        .onChange(of: value) { _, newValue in
            if !isEditing { editText = String(newValue) }
        }
    }

    private func commit() {
        isEditing = false
        guard let parsed = Int(editText) else {
            editText = String(value)
            return
        }
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        onCommit(clamped)
        editText = String(clamped)
    }
}

private struct FloatInputField: View {
    let value: CGFloat
    let suffix: String
    let onCommit: (CGFloat) -> Void

    @State private var editText: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $editText)
                .font(.system(size: 11))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        isEditing = true
                    } else {
                        commit()
                    }
                }
                .onChange(of: editText) { _, newText in
                    guard isEditing else { return }
                    if let parsed = Double(newText) {
                        let next = CGFloat(parsed)
                        if next != value { onCommit(next) }
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

    private func commit() {
        isEditing = false
        guard let parsed = Double(editText) else {
            editText = formatted(value)
            return
        }
        let clamped = CGFloat(parsed)
        onCommit(clamped)
        editText = formatted(clamped)
    }
}
