import SwiftUI

struct StatusBarView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var zoomText: String = "100"
    @State private var isEditingZoom: Bool = false
    @FocusState private var zoomFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(coordinateText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))

            Spacer()

            Text(editor.document.settings.unit.abbreviation)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))

            statusDivider

            Button(action: { editor.zoomOut() }) {
                Image(systemName: "minus").font(.system(size: 12))
                    .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
            }
            .buttonStyle(.plain)

            // Editable zoom percentage
            HStack(spacing: 2) {
                TextField("", text: $zoomText)
                    .font(.system(size: 10))
                    .textFieldStyle(.plain)
                    .focused($zoomFocused)
                    .frame(width: 30)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { commitZoom() }
                    .onChange(of: zoomFocused) { _, focused in
                        if focused {
                            isEditingZoom = true
                        } else {
                            commitZoom()
                        }
                    }

                Text("%")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(DesignTokens.bgInput(colorScheme))
            .cornerRadius(3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(zoomFocused ? DesignTokens.accent : DesignTokens.border(colorScheme), lineWidth: 1)
            )
            .onChange(of: editor.transform.zoomPercentage) { _, newValue in
                if !isEditingZoom { zoomText = "\(newValue)" }
            }
            .onAppear { zoomText = "\(editor.transform.zoomPercentage)" }

            Button(action: { editor.zoomIn() }) {
                Image(systemName: "plus").font(.system(size: 12))
                    .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
            }
            .buttonStyle(.plain)

            statusDivider

            Button(action: { editor.zoomToFit() }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12))
                    .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(DesignTokens.bgStatusbar(colorScheme))
        .overlay(alignment: .top) {
            Rectangle().fill(DesignTokens.border(colorScheme)).frame(height: 1)
        }
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(DesignTokens.border(colorScheme))
            .frame(width: 1, height: 14)
    }

    private var coordinateText: String {
        let pos = editor.cursorWorldPosition
        let unit = editor.document.settings.unit
        let x = unit.fromMillimeters(pos.x)
        let y = unit.fromMillimeters(pos.y)
        return String(format: "X: %.1f  Y: %.1f", x, y)
    }

    private func commitZoom() {
        isEditingZoom = false
        guard let value = Int(zoomText), value > 0 else {
            zoomText = "\(editor.transform.zoomPercentage)"
            return
        }
        let clamped = max(1, min(1600, value))
        editor.setZoomPercentage(CGFloat(clamped))
        zoomText = "\(editor.transform.zoomPercentage)"
    }
}
