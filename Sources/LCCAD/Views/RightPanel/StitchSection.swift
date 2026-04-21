import SwiftUI

struct StitchSection: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var iron: PrickingIron? {
        editor.activePrickingIron
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STITCH SETTINGS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.stitchColor)
                .tracking(0.5)

            // Iron Type row
            HStack(spacing: 8) {
                Text("Iron Type")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))

                Spacer()

                Picker("", selection: ironBinding) {
                    ForEach(editor.document.prickingIrons) { iron in
                        Text(iron.name).tag(iron.id)
                    }
                }
                .labelsHidden()
                .frame(height: 28)

                Button {
                    editor.showPrickingIronSheet = true
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
                }
                .buttonStyle(.plain)
                .help("Pricking Iron Settings")
            }

            // Pitch row
            HStack(spacing: 8) {
                Text("Pitch")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))

                Spacer()

                HStack(spacing: 4) {
                    Text(String(format: "%.1f mm", iron?.pitch ?? 4.0))
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textPrimary(colorScheme))
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
        .padding(12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.borderLight(colorScheme)).frame(height: 1)
        }
    }

    private var ironBinding: Binding<UUID> {
        Binding(
            get: { editor.selectedIronId ?? editor.document.prickingIrons.first?.id ?? UUID() },
            set: { editor.selectedIronId = $0 }
        )
    }
}
