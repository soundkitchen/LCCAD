import SwiftUI

struct RightPanelView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Properties")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary(colorScheme))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(DesignTokens.bgSection(colorScheme))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DesignTokens.border(colorScheme)).frame(height: 1)
                }

                if let selectedId = editor.selectedShapeId,
                   let shape = editor.findShape(id: selectedId) {
                    PositionSection(editor: editor, boundingBox: shape.boundingBox, unit: editor.document.settings.unit)
                    SizeSection(boundingBox: shape.boundingBox, unit: editor.document.settings.unit)

                    if case .text = shape {
                        TextSection(editor: editor)
                    } else {
                        StrokeSection(editor: editor, stroke: shape.stroke)
                    }

                    if case .arc = shape {
                        ArcSection()
                    }

                    StitchSection(editor: editor)
                } else {
                    VStack {
                        Spacer().frame(height: 40)
                        Text("No selection")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textMuted(colorScheme))
                    }
                }

                Spacer()
            }
        }
        .background(DesignTokens.bgPanel(colorScheme))
    }
}
