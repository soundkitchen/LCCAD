import SwiftUI

/// Bulk bevel sheet. Rounds every detected corner across the current selection
/// (lines, rectangles, straight bézier corners) with a single radius. Triggered
/// from Arrange ▸ Bevel… while shapes are selected.
struct BevelSheet: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var radius: CGFloat = 2.0

    private var cornerCount: Int { editor.bevelableCornerCount(radius: radius) }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
            actionBar
        }
        .frame(width: 440, height: 230)
        .background(DesignTokens.bgPanel(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { radius = editor.bevelRadius }
    }

    private var titleBar: some View {
        HStack {
            Spacer()
            Text("Bevel")
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
            Text("BEVEL")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(DesignTokens.textMuted(colorScheme))

            HStack(spacing: 8) {
                Text("Radius")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                    .frame(width: 80, alignment: .leading)

                NumberBoxField(value: radius, range: 0.1...100) { radius = $0 }

                Text("mm")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))
            }

            Text(countMessage)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
    }

    private var countMessage: String {
        switch cornerCount {
        case 0: return "No corners to round"
        case 1: return "1 corner will be rounded"
        default: return "\(cornerCount) corners will be rounded"
        }
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
                editor.bevelRadius = radius
                editor.bevelSelectedCorners(radius: radius)
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
            .disabled(cornerCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignTokens.border(colorScheme)).frame(height: 1)
        }
    }
}
