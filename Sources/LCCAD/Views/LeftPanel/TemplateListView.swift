import SwiftUI

/// The Templates tab content in the left panel. Lists saved templates from the
/// global library, lets the user save the current selection, and places a
/// template onto the canvas with a single click (click-to-place).
struct TemplateListView: View {
    @Bindable var editor: EditorViewModel
    @ObservedObject private var store = TemplateLibraryStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            actionBar

            if store.templates.isEmpty {
                emptyState
            } else {
                templateList
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 4) {
            Button(action: { editor.showSaveTemplateSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 12))
                    Text("選択を保存").font(.system(size: 11))
                }
                .foregroundStyle(editor.hasSelection
                    ? DesignTokens.textSecondary(colorScheme)
                    : DesignTokens.textMuted(colorScheme))
            }
            .buttonStyle(.plain)
            .disabled(!editor.hasSelection)

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.borderLight(colorScheme)).frame(height: 1)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("テンプレートがありません")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
            Text("図形を選択して「選択を保存」")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.textMuted(colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var templateList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.templates) { template in
                    templateRow(template)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func templateRow(_ template: Template) -> some View {
        let isPending = editor.pendingTemplate?.id == template.id
        return HStack(spacing: 8) {
            TemplateThumbnail(template: template, colorScheme: colorScheme)
                .frame(width: 36, height: 36)
                .background(DesignTokens.bgSection(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(DesignTokens.borderLight(colorScheme), lineWidth: 1)
                )

            Text(template.name)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textPrimary(colorScheme))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(action: { store.delete(id: template.id) }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.iconSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .help("テンプレートを削除")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(isPending ? DesignTokens.bgToolActive(colorScheme) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { editor.beginTemplatePlacement(template) }
        .help("クリックでキャンバスに配置")
    }
}

// MARK: - Thumbnail

/// Renders a template's shapes scaled to fit a square swatch. Reuses
/// `CanvasRenderer` so previews match the canvas exactly, but recolors strokes to
/// a theme-aware tone so they stay legible on the swatch background in both modes.
struct TemplateThumbnail: View {
    let template: Template
    var colorScheme: ColorScheme

    var body: some View {
        Canvas { context, size in
            guard let box = template.boundingBox else { return }

            let pad: CGFloat = 5
            let availW = size.width - pad * 2
            let availH = size.height - pad * 2
            guard availW > 0, availH > 0 else { return }

            // Fit scale per axis; a near-zero dimension (dots, axis-aligned lines) yields
            // .infinity for that axis so the other governs. Clamp to a sane max so a
            // degenerate/tiny template still renders (never blanks) instead of zooming away.
            let maxScale: CGFloat = 10
            let sx = box.width  > 0.0001 ? availW / box.width  : .infinity
            let sy = box.height > 0.0001 ? availH / box.height : .infinity
            let fit = min(sx, sy)
            let scale = fit.isFinite ? min(fit, maxScale) : maxScale

            var transform = CanvasTransform()
            transform.scale = scale
            transform.offset = CGPoint(
                x: pad + (availW - box.width * scale) / 2 - box.minX * scale,
                y: pad + (availH - box.height * scale) / 2 - box.minY * scale
            )

            let strokeColor: CodableColor = colorScheme == .dark
                ? CodableColor(r: 0.8, g: 0.8, b: 0.8)
                : CodableColor(r: 0.2, g: 0.2, b: 0.2)

            let renderer = CanvasRenderer(transform: transform, colorScheme: colorScheme)
            for shape in template.shapes {
                renderer.draw(shape: Self.recolored(shape, strokeColor), in: context)
            }
        }
    }

    /// Recolor a shape (and group descendants) so previews are legible regardless
    /// of the original stroke color.
    private static func recolored(_ shape: AnyShape, _ color: CodableColor) -> AnyShape {
        var s = shape
        if case .group(var group) = s {
            group.children = group.children.map { recolored($0, color) }
            s = .group(group)
        }
        s.stroke.color = color
        return s
    }
}
