import SwiftUI

struct PageSection: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var layout: PageLayoutSettings {
        editor.document.settings.pageLayout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            paperSettingsSection
            pagesListSection
            if editor.selectedPage != nil {
                selectedPageSection
            }
            layoutSettingsSection
        }
    }

    // MARK: - Paper Settings (shared across all pages)

    private var paperSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAPER")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .tracking(0.5)

            // Paper size
            HStack(spacing: 8) {
                Text("Size")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                    .frame(width: 48, alignment: .leading)
                Picker("", selection: paperSizeBinding) {
                    ForEach(PaperSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .labelsHidden()
            }

            // Orientation
            HStack(spacing: 8) {
                Text("Orient")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                    .frame(width: 48, alignment: .leading)
                Picker("", selection: orientationBinding) {
                    Text("Portrait").tag(PageOrientation.portrait)
                    Text("Landscape").tag(PageOrientation.landscape)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Margin
            HStack(spacing: 8) {
                Text("Margin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                    .frame(width: 48, alignment: .leading)
                EditablePropertyField(
                    label: "",
                    value: layout.margin,
                    suffix: "mm",
                    range: 0...50
                ) { newVal in
                    editor.updatePageLayout(actionName: "Edit Margin") { $0.margin = newVal }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.borderLight(colorScheme)).frame(height: 1)
        }
    }

    // MARK: - Pages List

    private var pagesListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAGES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .tracking(0.5)

            if layout.pages.isEmpty {
                Text("Click canvas to add a page")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(layout.pages.enumerated()), id: \.element.id) { index, page in
                        pageRow(index: index, page: page)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(DesignTokens.border(colorScheme), lineWidth: 1)
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.borderLight(colorScheme)).frame(height: 1)
        }
    }

    private func pageRow(index: Int, page: PrintPage) -> some View {
        let isSelected = page.id == editor.selectedPageId
        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .semibold))
            let pos = page.origin
            Text(String(format: "(%.0f, %.0f)", pos.x, pos.y))
                .font(.system(size: 11))
        }
        .foregroundStyle(isSelected ? DesignTokens.textOnAccent : DesignTokens.textPrimary(colorScheme))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32)
        .background(isSelected ? DesignTokens.accent : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            editor.selectedPageId = page.id
        }
    }

    // MARK: - Selected Page (position only)

    private var selectedPageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POSITION")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .tracking(0.5)

            HStack(spacing: 8) {
                EditablePropertyField(
                    label: "X",
                    value: editor.selectedPage?.origin.x ?? 0,
                    suffix: "mm"
                ) { newVal in
                    editor.updatePageProperty { $0.origin.x = newVal }
                }
                EditablePropertyField(
                    label: "Y",
                    value: editor.selectedPage?.origin.y ?? 0,
                    suffix: "mm"
                ) { newVal in
                    editor.updatePageProperty { $0.origin.y = newVal }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.borderLight(colorScheme)).frame(height: 1)
        }
    }

    // MARK: - Layout Settings

    private var layoutSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAYOUT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .tracking(0.5)

            HStack(spacing: 8) {
                Text("Overlap")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                    .frame(width: 48, alignment: .leading)
                EditablePropertyField(
                    label: "",
                    value: layout.overlapMM,
                    suffix: "mm",
                    range: 0...50
                ) { newVal in
                    editor.updatePageLayout(actionName: "Edit Overlap") { $0.overlapMM = newVal }
                }
            }

            Toggle("Show Frames", isOn: Binding(
                get: { editor.document.settings.pageLayout.showPageFrames },
                set: { editor.document.settings.pageLayout.showPageFrames = $0 }
            ))
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.textPrimary(colorScheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.borderLight(colorScheme)).frame(height: 1)
        }
    }

    // MARK: - Bindings

    private var paperSizeBinding: Binding<PaperSize> {
        Binding(
            get: { layout.paperSize },
            set: { newSize in
                editor.updatePageLayout(actionName: "Change Paper Size") { $0.paperSize = newSize }
            }
        )
    }

    private var orientationBinding: Binding<PageOrientation> {
        Binding(
            get: { layout.orientation },
            set: { newOrientation in
                editor.updatePageLayout(actionName: "Change Orientation") { $0.orientation = newOrientation }
            }
        )
    }
}
