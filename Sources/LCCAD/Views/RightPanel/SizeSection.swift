import SwiftUI

struct SizeSection: View {
    @Bindable var editor: EditorViewModel
    let boundingBox: CGRect
    let unit: LengthUnit
    var rotation: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    /// Selections containing shapes that cannot scale non-uniformly
    /// (Arc, Text, rotated Rect/Ellipse) always resize proportionally.
    private var lockForced: Bool { editor.selectionRequiresUniformScale }
    private var lockActive: Bool { lockForced || editor.isSizeAspectLocked }

    var body: some View {
        PropertySection(title: "Size") {
            HStack(spacing: 8) {
                EditablePropertyField(
                    label: "W",
                    value: unit.fromMillimeters(boundingBox.width),
                    range: 0.1...10000,
                    onCommit: { newValue in
                        editor.setSelectedShapeSize(width: unit.toMillimeters(newValue))
                    }
                )
                EditablePropertyField(
                    label: "H",
                    value: unit.fromMillimeters(boundingBox.height),
                    range: 0.1...10000,
                    onCommit: { newValue in
                        editor.setSelectedShapeSize(height: unit.toMillimeters(newValue))
                    }
                )
            }

            HStack(spacing: 8) {
                // Rotation field
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))
                        .frame(width: 14)

                    Text(String(format: "%.1f°", rotation))
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

                // Aspect-ratio lock toggle
                Button(action: { editor.isSizeAspectLocked.toggle() }) {
                    Image(systemName: lockActive ? "lock" : "lock.open")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            lockActive && !lockForced
                                ? DesignTokens.accent
                                : DesignTokens.iconSecondary(colorScheme)
                        )
                }
                .buttonStyle(.plain)
                .disabled(lockForced)
                .frame(maxWidth: .infinity, maxHeight: 28)
                .cornerRadius(4)
                .help(lockForced
                      ? "Selection resizes proportionally (contains arc, text, or rotated shape)"
                      : (lockActive ? "Unlock aspect ratio" : "Lock aspect ratio"))
            }
        }
    }
}
