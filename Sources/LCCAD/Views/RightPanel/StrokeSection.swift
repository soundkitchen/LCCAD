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

                EditablePropertyField(
                    label: "W",
                    value: stroke.width,
                    suffix: "mm",
                    range: 0.01...100,
                    onCommit: { newWidth in
                        editor.updateStroke { $0.width = newWidth }
                    }
                )
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
