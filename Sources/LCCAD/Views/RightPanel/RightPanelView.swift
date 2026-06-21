import SwiftUI

struct RightPanelView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(editor.currentTool == .page ? "Page Layout" : "Properties")
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

                if editor.currentTool == .page {
                    PageSection(editor: editor)
                } else if editor.isMultiSelection {
                    // Multi-selection: show count and combined bounding box
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(editor.selectedShapeIds.count) items selected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                    }

                    if let bbox = editor.selectionBoundingBox {
                        PositionSection(editor: editor, boundingBox: bbox, unit: editor.document.settings.unit)
                        SizeSection(boundingBox: bbox, unit: editor.document.settings.unit)
                    }

                    // Show stroke section for batch editing (uses first selected shape's stroke)
                    if let firstShape = editor.selectedShapes.first {
                        if case .text = firstShape {
                            // skip text section for multi-select
                        } else {
                            StrokeSection(editor: editor, stroke: firstShape.stroke)
                        }
                    }
                } else if editor.isSingleSelection,
                          let selectedId = editor.selectedShapeIds.first,
                          let shape = editor.findShape(id: selectedId) {
                    PositionSection(editor: editor, boundingBox: shape.boundingBox, unit: editor.document.settings.unit)
                    SizeSection(
                        boundingBox: shape.boundingBox,
                        unit: editor.document.settings.unit,
                        rotation: rotationDegrees(for: shape)
                    )

                    if case .group(let group) = shape {
                        Text("Group (\(group.children.count) items)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                        StrokeSection(editor: editor, stroke: shape.stroke)
                    } else if case .text = shape {
                        TextSection(editor: editor)
                    } else if case .dimensionLine = shape {
                        DimensionLineSection(editor: editor)
                    } else {
                        StrokeSection(editor: editor, stroke: shape.stroke)
                    }

                    if case .arc = shape {
                        ArcSection()
                    }

                    if case .dimensionLine = shape {
                        // Dimension is self-contained; no stitch section.
                    } else {
                        StitchSection(editor: editor)
                    }
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

    private func rotationDegrees(for shape: AnyShape) -> CGFloat {
        let radians: CGFloat
        switch shape {
        case .rectangle(let r): radians = r.rotation
        case .text(let t): radians = t.rotation
        case .ellipse(let e): radians = e.rotation
        default: return 0
        }
        return radians * 180 / .pi
    }
}
