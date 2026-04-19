import SwiftUI

struct SizeSection: View {
    let boundingBox: CGRect
    let unit: LengthUnit
    var rotation: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PropertySection(title: "Size") {
            HStack(spacing: 8) {
                PropertyField(label: "W", value: unit.fromMillimeters(boundingBox.width))
                PropertyField(label: "H", value: unit.fromMillimeters(boundingBox.height))
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

                // Lock aspect ratio button
                Button(action: {}) {
                    Image(systemName: "lock")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: 28)
                .cornerRadius(4)
            }
        }
    }
}
