import SwiftUI

struct ToolbarView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 2) {
            // Drawing tools
            ForEach(DrawingTool.drawingTools, id: \.self) { tool in
                toolButton(tool)
            }

            toolbarSeparator

            // Editing tools (selectable like drawing tools)
            ForEach(DrawingTool.editingTools, id: \.self) { tool in
                toolButton(tool)
            }

            toolbarSeparator

            // Stitch tools (warm color)
            stitchToolButton(icon: "grid", label: "Auto Stitch") {
                editor.autoStitchSelectedShape()
            }
            stitchToolButton(icon: "eye", label: "Stitch Simulator") {
                // TODO: Stitch simulator not yet implemented
            }

            Spacer()

            // Undo / Redo
            Button(action: { undoManager?.undo() }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .disabled(undoManager?.canUndo != true)
            .help("Undo (⌘Z)")

            Button(action: { undoManager?.redo() }) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .disabled(undoManager?.canRedo != true)
            .help("Redo (⇧⌘Z)")
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(DesignTokens.bgToolbar(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.border(colorScheme)).frame(height: 1)
        }
    }

    // MARK: - Drawing tool button (selectable)

    private func toolButton(_ tool: DrawingTool) -> some View {
        Button(action: {
            editor.selectTool(tool)
        }) {
            Image(systemName: tool.iconName)
                .font(.system(size: 16))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(editor.currentTool == tool ? DesignTokens.bgToolActive(colorScheme) : Color.clear)
                )
                .foregroundStyle(editor.currentTool == tool ? DesignTokens.accent : DesignTokens.iconPrimary(colorScheme))
        }
        .buttonStyle(.plain)
        .help(tool.tooltip)
    }

    // MARK: - Stitch tool button (warm accent color)

    private func stitchToolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .foregroundStyle(DesignTokens.stitchColor)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Separator

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(DesignTokens.border(colorScheme))
            .frame(width: 1, height: 20)
    }
}
