import SwiftUI

struct LeftPanelView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("Layers", index: 0)
                tabButton("Templates", index: 1)
            }
            .frame(height: 36)
            .background(DesignTokens.bgSection(colorScheme))
            .overlay(alignment: .bottom) {
                Rectangle().fill(DesignTokens.border(colorScheme)).frame(height: 1)
            }

            if selectedTab == 0 {
                LayerListView(editor: editor)
            } else {
                TemplateListPlaceholder()
            }
        }
        .background(DesignTokens.bgPanel(colorScheme))
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            Text(title)
                .font(.system(size: 11, weight: selectedTab == index ? .semibold : .regular))
                .foregroundStyle(selectedTab == index ? DesignTokens.accent : DesignTokens.textSecondary(colorScheme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if selectedTab == index {
                        Rectangle()
                            .fill(DesignTokens.accent)
                            .frame(height: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct TemplateListPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            Spacer()
            Text("Templates")
                .foregroundStyle(DesignTokens.textSecondary(colorScheme))
                .font(.system(size: 12))
            Spacer()
        }
    }
}
