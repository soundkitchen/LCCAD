import SwiftUI

struct ArcSection: View {
    var radius: CGFloat = 0
    var angle: CGFloat = 0
    var startAngle: CGFloat = 0
    var endAngle: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PropertySection(title: "Arc / Curve") {
            HStack(spacing: 8) {
                PropertyField(label: "R", value: radius)
                // Angle field with icon
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))
                        .frame(width: 14)

                    Text(String(format: "%.0f°", angle))
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
                Text("Start")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))

                Spacer()

                Text(String(format: "%.0f°", startAngle))
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textPrimary(colorScheme))

                Text("End")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))

                Spacer()
                    .frame(width: 8)

                Text(String(format: "%.0f°", endAngle))
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textPrimary(colorScheme))
            }
        }
    }
}
