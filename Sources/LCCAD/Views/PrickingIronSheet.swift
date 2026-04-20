import SwiftUI

struct PrickingIronSheet: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIronId: UUID?
    @State private var editingIron: PrickingIron?

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            contentArea
            actionBar
        }
        .frame(width: 440, height: 520)
        .background(DesignTokens.bgPanel(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            selectedIronId = editor.selectedIronId ?? editor.document.prickingIrons.first?.id
            if let id = selectedIronId {
                editingIron = editor.document.prickingIrons.first { $0.id == id }
            }
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Spacer()
            Text("Pricking Iron Settings")
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

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            ironList
            detailsSection
        }
        .padding(16)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Iron List

    private var ironList: some View {
        VStack(spacing: 0) {
            ForEach(Array(editor.document.prickingIrons.enumerated()), id: \.element.id) { index, iron in
                VStack(spacing: 0) {
                    if index > 0 {
                        Rectangle()
                            .fill(DesignTokens.borderLight(colorScheme))
                            .frame(height: 1)
                    }
                    ironRow(iron)
                }
            }
        }
        .background(DesignTokens.bgPanel(colorScheme))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DesignTokens.border(colorScheme), lineWidth: 1)
        )
    }

    private func ironRow(_ iron: PrickingIron) -> some View {
        HStack(spacing: 8) {
            holeTypeIcon(iron.holeType)
                .foregroundStyle(DesignTokens.stitchColor)
                .frame(width: 16, height: 16)

            Text(iron.name)
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textPrimary(colorScheme))
                .lineLimit(1)

            Spacer()

            Text("\(iron.teeth)\u{5203} \(Int(iron.holeAngle * 180 / .pi))\u{00B0}")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(selectedIronId == iron.id
            ? Color(hex: 0x4A90D9, opacity: 0.1)
            : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIronId = iron.id
            editingIron = iron
        }
    }

    @ViewBuilder
    private func holeTypeIcon(_ type: HoleType) -> some View {
        switch type {
        case .diamond:
            Image(systemName: "diamond.fill")
                .font(.system(size: 10))
        case .french:
            Image(systemName: "line.diagonal")
                .font(.system(size: 10))
        case .round:
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
        case .flat:
            Image(systemName: "minus")
                .font(.system(size: 10))
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DETAILS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textMuted(colorScheme))
                .tracking(0.5)

            if editingIron != nil {
                detailsForm
            } else {
                Text("Select a pricking iron to edit")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
    }

    private var detailsForm: some View {
        VStack(spacing: 6) {
            // Type row
            detailRow(label: "Type") {
                Picker("", selection: holeTypeBinding) {
                    ForEach(HoleType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            // Pitch row
            detailRow(label: "Pitch") {
                HStack(spacing: 4) {
                    TextField("", text: pitchBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                    Text("mm")
                        .font(.system(size: 9))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))
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

            // Teeth row
            detailRow(label: "Teeth") {
                HStack(spacing: 4) {
                    TextField("", text: teethBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
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

            // Angle row
            detailRow(label: "Angle") {
                HStack(spacing: 4) {
                    TextField("", text: angleBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                    Text("\u{00B0}")
                        .font(.system(size: 9))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))
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

            // Size row
            detailRow(label: "Size") {
                HStack(spacing: 4) {
                    TextField("", text: sizeBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                    Text("mm")
                        .font(.system(size: 9))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))
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
        }
    }

    private func detailRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .frame(width: 50, alignment: .leading)

            content()
        }
        .frame(height: 28)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                addNewIron()
            } label: {
                Text("+ Add")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textOnAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(DesignTokens.accent)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            Button {
                deleteSelectedIron()
            } label: {
                Text("Delete")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary(colorScheme))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignTokens.border(colorScheme), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(editor.document.prickingIrons.count <= 1)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textOnAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(DesignTokens.accent)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignTokens.border(colorScheme)).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func addNewIron() {
        let newIron = PrickingIron(name: "New Iron", holeType: .diamond)
        editor.addPrickingIron(newIron)
        selectedIronId = newIron.id
        editingIron = newIron
    }

    private func deleteSelectedIron() {
        guard let id = selectedIronId,
              editor.document.prickingIrons.count > 1 else { return }
        editor.deletePrickingIron(id: id)
        selectedIronId = editor.document.prickingIrons.first?.id
        if let newId = selectedIronId {
            editingIron = editor.document.prickingIrons.first { $0.id == newId }
        } else {
            editingIron = nil
        }
    }

    private func commitEditing() {
        guard let iron = editingIron else { return }
        editor.updatePrickingIron(iron)
    }

    // MARK: - Bindings

    private var holeTypeBinding: Binding<HoleType> {
        Binding(
            get: { editingIron?.holeType ?? .diamond },
            set: { newValue in
                editingIron?.holeType = newValue
                commitEditing()
            }
        )
    }

    private var pitchBinding: Binding<String> {
        Binding(
            get: { String(format: "%.1f", editingIron?.pitch ?? 4.0) },
            set: { newValue in
                if let value = Double(newValue), value > 0 {
                    editingIron?.pitch = CGFloat(value)
                    commitEditing()
                }
            }
        )
    }

    private var teethBinding: Binding<String> {
        Binding(
            get: { "\(editingIron?.teeth ?? 4)" },
            set: { newValue in
                if let value = Int(newValue), value > 0 {
                    editingIron?.teeth = value
                    commitEditing()
                }
            }
        )
    }

    private var angleBinding: Binding<String> {
        Binding(
            get: {
                let radians = editingIron?.holeAngle ?? 0
                return String(format: "%.0f", radians * 180 / .pi)
            },
            set: { newValue in
                if let degrees = Double(newValue) {
                    editingIron?.holeAngle = CGFloat(degrees) * .pi / 180
                    commitEditing()
                }
            }
        )
    }

    private var sizeBinding: Binding<String> {
        Binding(
            get: { String(format: "%.1f", editingIron?.holeSize ?? 1.0) },
            set: { newValue in
                if let value = Double(newValue), value > 0 {
                    editingIron?.holeSize = CGFloat(value)
                    commitEditing()
                }
            }
        )
    }
}
