import SwiftUI

/// Box stitch (駒合わせ) sheet: matches the hole count across the two selected parts
/// so hand-stitching lines up (boxes, cylinders, coin cases). While the sheet is up
/// the canvas shows ghost holes on both parts, updating live as the inputs change.
/// Triggered from Stitch ▸ Box Stitch… / the toolbar with exactly two runs selected.
struct BoxStitchSheet: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum PolicyChoice: String, CaseIterable, Identifiable {
        case larger, smaller, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .larger: return "Larger"
            case .smaller: return "Smaller"
            case .custom: return "Custom"
            }
        }
    }

    @State private var choice: PolicyChoice = .larger
    @State private var customCount: Int = 10
    @State private var estimate: BoxStitchEstimate?
    /// Presented from within this sheet: a second `.sheet` on `MainEditorView` cannot
    /// appear while this one is up (one sheet per presenting view), so the iron sheet
    /// is nested here with its own flag to avoid fighting over the shared one.
    @State private var showIronSheet: Bool = false

    private var policy: BoxStitchPolicy {
        switch choice {
        case .larger: return .matchLarger
        case .smaller: return .matchSmaller
        case .custom: return .custom(customCount)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
            actionBar
        }
        .frame(width: 440, height: 520)
        .background(DesignTokens.bgPanel(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            // Seed Custom with the larger natural count so switching to it
            // starts from a sensible value instead of an arbitrary default.
            if let seed = editor.boxStitchEstimate(policy: .matchLarger) {
                customCount = seed.resolvedCount
            }
            refresh()
        }
        .onChange(of: choice) { _, _ in refresh() }
        .onChange(of: customCount) { _, _ in refresh() }
        .onChange(of: editor.selectedIronId) { _, _ in refresh() }
        .sheet(isPresented: $showIronSheet, onDismiss: {
            // The selected iron's pitch may have been edited in place, which the
            // selectedIronId onChange can't see — recompute unconditionally.
            refresh()
        }) {
            PrickingIronSheet(editor: editor)
        }
    }

    /// Recompute the dry run and push the ghost holes to the canvas.
    private func refresh() {
        estimate = editor.boxStitchEstimate(policy: policy)
        if let estimate, let iron = editor.activePrickingIron {
            editor.boxStitchPreview = BoxStitchPreview(
                holesA: estimate.runA.holes,
                holesB: estimate.runB.holes,
                holeType: iron.holeType,
                holeSize: iron.holeSize
            )
        } else {
            editor.boxStitchPreview = nil
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Spacer()
            Text("Box Stitch")
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

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("PARTS")
            partRow(title: "Part A (longer)", run: estimate?.runA, dot: DesignTokens.stitchColor)
            partRow(title: "Part B (shorter)", run: estimate?.runB, dot: DesignTokens.accent)

            Rectangle()
                .fill(DesignTokens.borderLight(colorScheme))
                .frame(height: 1)

            sectionHeader("HOLE COUNT")
            ironRow
            policyPicker
            countRow
            resultBlock

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(DesignTokens.textMuted(colorScheme))
    }

    private func partRow(title: String, run: BoxStitchEstimate.Run?, dot: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary(colorScheme))
                Text(run.map(detailText) ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
            }
        }
    }

    private func detailText(_ run: BoxStitchEstimate.Run) -> String {
        let shape = run.isClosed ? "Closed" : "Open"
        let corners = run.cornerCount == 0 ? "Smooth" : "\(run.cornerCount) corners"
        return String(format: "%.1f mm ・ %@ ・ %@ ・ %d holes", run.length, shape, corners, run.naturalCount)
    }

    private var ironRow: some View {
        HStack(spacing: 6) {
            Text("Iron")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .frame(width: 60, alignment: .leading)

            Picker("", selection: ironBinding) {
                ForEach(editor.document.prickingIrons) { iron in
                    Text(iron.name).tag(iron.id)
                }
            }
            .labelsHidden()
            .frame(height: 28)

            Button {
                showIronSheet = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .help("Pricking Iron Settings")
        }
    }

    private var ironBinding: Binding<UUID> {
        Binding(
            get: { editor.selectedIronId ?? editor.document.prickingIrons.first?.id ?? UUID() },
            set: { editor.selectedIronId = $0 }
        )
    }

    private var policyPicker: some View {
        Picker("", selection: $choice) {
            ForEach(PolicyChoice.allCases) { choice in
                Text(choice.label).tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var countRow: some View {
        HStack(spacing: 6) {
            Text("Count")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .frame(width: 60, alignment: .leading)

            NumberBoxField(
                value: CGFloat(choice == .custom ? customCount : (estimate?.resolvedCount ?? customCount)),
                range: 1...999,
                fractionDigits: 0
            ) {
                customCount = Int($0.rounded())
            }
            .frame(width: 64)

            Text("holes")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.textMuted(colorScheme))
        }
        .opacity(choice == .custom ? 1 : 0.4)
        .disabled(choice != .custom)
    }

    // MARK: - Result

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(resultTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary(colorScheme))

            if let estimate {
                HStack(spacing: 12) {
                    pitchItem(label: "Part A", pitch: estimate.runA.effectivePitch, dot: DesignTokens.stitchColor)
                    pitchItem(label: "Part B", pitch: estimate.runB.effectivePitch, dot: DesignTokens.accent)
                }
                ForEach(warnings, id: \.self) { warning in
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                        Text(warning)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(DesignTokens.warning(colorScheme))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.bgSection(colorScheme))
        .cornerRadius(4)
    }

    private var resultTitle: String {
        guard let estimate else { return "Select exactly two parts" }
        return "\(estimate.resolvedCount) holes per part"
    }

    private func pitchItem(label: String, pitch: CGFloat, dot: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(String(format: "%@ ・ pitch %.1f mm", label, pitch))
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
        }
    }

    private var warnings: [String] {
        guard let estimate, let iron = editor.activePrickingIron else { return [] }
        var result: [String] = []
        if estimate.wasClamped {
            result.append("Count raised to \(estimate.resolvedCount) — every corner needs a hole")
        }
        for (name, run) in [("Part A", estimate.runA), ("Part B", estimate.runB)] where iron.pitch > 0 {
            let deviation = abs(run.effectivePitch - iron.pitch) / iron.pitch
            if deviation > 0.25 {
                result.append(String(format: "%@ pitch deviates %.0f%% from iron pitch (%.1f mm)",
                                     name, deviation * 100, iron.pitch))
            }
        }
        if estimate.runA.isClosed != estimate.runB.isClosed {
            result.append("Parts differ: one is open, one is closed")
        }
        for (name, run) in [("Part A", estimate.runA), ("Part B", estimate.runB)] where run.hasExistingStitchLine {
            result.append("Existing stitch on \(name) will be replaced")
        }
        return result
    }

    // MARK: - Action bar

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
                // Keep the sheet open if the commit fell through (e.g. an undo while
                // the sheet was up changed the runs) so the failure isn't silent.
                if let estimate, editor.applyBoxStitch(count: estimate.resolvedCount) {
                    dismiss()
                } else {
                    NSSound.beep()
                    refresh()
                }
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
            .disabled(!(estimate?.canApply ?? false))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DesignTokens.border(colorScheme)).frame(height: 1)
        }
    }
}
