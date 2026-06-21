import SwiftUI

struct DimensionLineSection: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var dim: DimensionLineShape? {
        guard let id = editor.selectedShapeIds.first,
              let shape = editor.findShape(id: id),
              case .dimensionLine(let d) = shape else { return nil }
        return d
    }

    private var unit: LengthUnit { editor.document.settings.unit }

    var body: some View {
        if let dim {
            PropertySection(title: "Dimension") {
                // Type
                Picker("", selection: kindBinding(current: dim.kind)) {
                    ForEach(DimensionKind.allCases, id: \.self) { k in
                        Text(k.displayName).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Measured value (read-only) + Offset (editable)
                HStack(spacing: 8) {
                    PropertyField(label: "L", value: unit.fromMillimeters(dim.measuredValue), suffix: unit.abbreviation)
                    EditablePropertyField(label: "O", value: unit.fromMillimeters(dim.offset), suffix: unit.abbreviation) { newVal in
                        editor.updateDimensionProperty { $0.offset = unit.toMillimeters(newVal) }
                    }
                }

                // Label override (empty = auto)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Label")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))

                    TextField("Auto", text: labelBinding(current: dim.labelOverride ?? ""))
                        .font(.system(size: 11))
                        .textFieldStyle(.plain)
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
    }

    // MARK: - Bindings

    private func kindBinding(current: DimensionKind) -> Binding<DimensionKind> {
        Binding(
            get: { current },
            set: { newValue in
                editor.updateDimensionProperty { $0.kind = newValue }
                editor.currentDimensionKind = newValue
            }
        )
    }

    private func labelBinding(current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { newValue in
                editor.updateDimensionProperty { $0.labelOverride = newValue.isEmpty ? nil : newValue }
            }
        )
    }
}
