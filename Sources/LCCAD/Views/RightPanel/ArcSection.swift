import SwiftUI

struct ArcSection: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var arc: ArcShape? {
        guard let id = editor.selectedShapeIds.first,
              let shape = editor.findShape(id: id),
              case .arc(let a) = shape else { return nil }
        return a
    }

    private var unit: LengthUnit { editor.document.settings.unit }

    var body: some View {
        if let arc {
            PropertySection(title: "Arc / Curve") {
                HStack(spacing: 8) {
                    EditablePropertyField(
                        label: "R",
                        value: unit.fromMillimeters(arc.radius),
                        range: 0.1...10_000
                    ) { newValue in
                        editor.updateArcProperty { $0.radius = unit.toMillimeters(newValue) }
                    }

                    // 中心角は R / Start / End から決まる導出値なので表示のみ
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.textMuted(colorScheme))
                            .frame(width: 14)

                        Text(String(format: "%.0f°", degrees(arc.angleSpan)))
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

                HStack(spacing: 8) {
                    EditablePropertyField(
                        label: "S",
                        value: degrees(arc.normalizeAngle(arc.startAngle)),
                        suffix: "°"
                    ) { newValue in
                        editor.updateArcProperty { $0.startAngle = radians(newValue) }
                    }
                    EditablePropertyField(
                        label: "E",
                        value: degrees(arc.normalizeAngle(arc.endAngle)),
                        suffix: "°"
                    ) { newValue in
                        editor.updateArcProperty { $0.endAngle = radians(newValue) }
                    }
                }
            }
        }
    }

    private func degrees(_ radians: CGFloat) -> CGFloat {
        radians * 180 / .pi
    }

    private func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }
}
