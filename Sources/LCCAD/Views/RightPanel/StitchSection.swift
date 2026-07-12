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

            // Mode row. Fixed/Variable only differ on open paths without corners;
            // for closed shapes and cornered outlines the engine always spaces evenly,
            // so the picker is dimmed there to avoid suggesting a choice that does nothing.
            let modeEnabled = editor.stitchModeAffectsSelection
            HStack(spacing: 8) {
                Text("Mode")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))

                Spacer()

                Picker("", selection: $editor.selectedStitchMode) {
                    ForEach(StitchMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(height: 28)
            }
            .opacity(modeEnabled ? 1 : 0.4)
            .disabled(!modeEnabled)
            .help(modeEnabled
                ? "Hole spacing mode for open paths"
                : "Closed shapes and corners are always evenly spaced — mode has no effect")

            // Count row: only meaningful in Even Count mode. Shares the mode row's
            // dimming — when corners force corner-anchored placement the count is
            // ignored just like the mode.
            let evenCountActive = editor.selectedStitchMode == .evenCount
            if evenCountActive {
                HStack(spacing: 8) {
                    Text("Count")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.textSecondary(colorScheme))

                    Spacer()

                    NumberBoxField(
                        value: CGFloat(editor.selectedStitchHoleCount),
                        range: 2...999,
                        fractionDigits: 0
                    ) {
                        editor.selectedStitchHoleCount = Int($0.rounded())
                    }
                    .frame(width: 64)
                }
                .opacity(modeEnabled ? 1 : 0.4)
                .disabled(!modeEnabled)
            }

            // Pitch row. In Even Count mode the pitch is ignored (the count decides
            // the spacing), so dim it — but only while the mode actually applies:
            // a cornered selection falls back to pitch-driven corner-anchored holes.
            let pitchUnused = evenCountActive && modeEnabled
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
            .opacity(pitchUnused ? 0.4 : 1)
            .help(pitchUnused ? "Even Count ignores the iron pitch — the count decides the spacing" : "")
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
