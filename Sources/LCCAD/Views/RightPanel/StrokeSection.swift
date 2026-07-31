import SwiftUI
import AppKit

struct StrokeSection: View {
    @Bindable var editor: EditorViewModel
    let stroke: StrokeStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PropertySection(title: "Stroke") {
            HStack(spacing: 8) {
                ColorPicker("", selection: colorBinding)
                    .labelsHidden()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignTokens.border(colorScheme), lineWidth: 1)
                    )

                // Width is fixed app-wide (StrokeStyle.fixedWidth) so printed
                // line thickness never shifts calibrated dimensions.
                Text("\(StrokeStyle.fixedWidth.formatted()) mm (fixed)")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))
            }

            HStack(spacing: 8) {
                Text("Style")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.textMuted(colorScheme))

                Menu {
                    ForEach(LineStyle.allCases, id: \.self) { style in
                        Button {
                            editor.updateStroke {
                                $0.lineStyle = style
                                $0.dashPattern = style.dashPattern
                            }
                        } label: {
                            Text(style.displayName)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        LineStylePreview(
                            style: stroke.lineStyle,
                            color: DesignTokens.textPrimary(colorScheme)
                        )
                        .frame(width: 30, height: 12)

                        Text(stroke.lineStyle.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textPrimary(colorScheme))

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignTokens.textMuted(colorScheme))
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(DesignTokens.bgInput(colorScheme))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DesignTokens.border(colorScheme), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(red: stroke.color.r, green: stroke.color.g, blue: stroke.color.b, opacity: stroke.color.a)
            },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.deviceRGB) {
                    editor.updateStroke {
                        $0.color = CodableColor(
                            r: components.redComponent,
                            g: components.greenComponent,
                            b: components.blueComponent,
                            a: components.alphaComponent
                        )
                    }
                }
            }
        )
    }
}
