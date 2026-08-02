import SwiftUI
import AppKit

struct TextSection: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var textShape: TextShape? {
        guard let id = editor.selectedShapeIds.first,
              let shape = editor.findShape(id: id),
              case .text(let t) = shape else { return nil }
        return t
    }

    private static let fontFamilies: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    /// サイズの許容範囲。ステッパーと直接入力の両方がこれを参照する (#50)
    private static let fontSizeRange: ClosedRange<CGFloat> = 1...200

    var body: some View {
        if let text = textShape {
            PropertySection(title: "Text") {
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text("Content")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))

                    TextEditor(text: contentBinding(current: text.content))
                        .font(.system(size: 11))
                        .frame(minHeight: 40, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(DesignTokens.bgInput(colorScheme))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(DesignTokens.border(colorScheme), lineWidth: 1)
                        )
                }

                // Font Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Font")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))

                    Picker("", selection: fontNameBinding(current: text.fontName)) {
                        ForEach(Self.fontFamilies, id: \.self) { family in
                            Text(family)
                                .font(.custom(family, size: 12))
                                .tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                // Font Size + Bold/Italic
                HStack(spacing: 8) {
                    Text("Size")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))
                        .frame(width: 26, alignment: .leading)

                    // 直接入力もステッパーと同じ範囲にクランプする (#50)。
                    // Undo がコミットごとに積まれるため liveCommit は無効化
                    NumberBoxField(
                        value: text.fontSize,
                        range: Self.fontSizeRange,
                        liveCommit: false
                    ) { newValue in
                        guard newValue != text.fontSize else { return }
                        editor.updateTextProperty { $0.fontSize = newValue }
                    }
                    .frame(width: 44)

                    Text("mm")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))

                    Stepper(
                        "",
                        value: fontSizeDoubleBinding(current: text.fontSize),
                        in: Double(Self.fontSizeRange.lowerBound)...Double(Self.fontSizeRange.upperBound),
                        step: 1
                    )
                    .labelsHidden()
                }

                // Style: Bold / Italic
                HStack(spacing: 8) {
                    Text("Style")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))
                        .frame(width: 26, alignment: .leading)

                    Toggle(isOn: boldBinding(current: text.isBold)) {
                        Image(systemName: "bold")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)

                    Toggle(isOn: italicBinding(current: text.isItalic)) {
                        Image(systemName: "italic")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)

                    Spacer()
                }

                // Alignment
                HStack(spacing: 8) {
                    Text("Align")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))
                        .frame(width: 26, alignment: .leading)

                    ForEach(TextAlignment.allCases, id: \.self) { alignment in
                        Button {
                            editor.updateTextProperty { $0.textAlignment = alignment }
                        } label: {
                            Image(systemName: alignmentIcon(alignment))
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .tint(text.textAlignment == alignment ? .accentColor : nil)
                    }

                    Spacer()
                }

                // Color
                HStack(spacing: 8) {
                    Text("Color")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.textMuted(colorScheme))
                        .frame(width: 26, alignment: .leading)

                    ColorPicker("", selection: colorBinding(current: text.stroke.color))
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - Helpers

    private func alignmentIcon(_ alignment: TextAlignment) -> String {
        switch alignment {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }

    // MARK: - Bindings

    private func contentBinding(current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { newValue in
                editor.updateTextProperty { $0.content = newValue }
            }
        )
    }

    /// ステッパー用バインディング。範囲は Stepper(in:) が保証するが、
    /// 念のためここでも fontSizeRange にクランプする
    private func fontSizeDoubleBinding(current: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { newValue in
                let clamped = min(max(CGFloat(newValue), Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
                guard clamped != current else { return }
                editor.updateTextProperty { $0.fontSize = clamped }
            }
        )
    }

    private func fontNameBinding(current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { newValue in
                editor.updateTextProperty { $0.fontName = newValue }
            }
        )
    }

    private func boldBinding(current: Bool) -> Binding<Bool> {
        Binding(
            get: { current },
            set: { newValue in
                editor.updateTextProperty { $0.isBold = newValue }
            }
        )
    }

    private func italicBinding(current: Bool) -> Binding<Bool> {
        Binding(
            get: { current },
            set: { newValue in
                editor.updateTextProperty { $0.isItalic = newValue }
            }
        )
    }

    private func colorBinding(current: CodableColor) -> Binding<Color> {
        Binding(
            get: { Color(red: current.r, green: current.g, blue: current.b, opacity: current.a) },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.deviceRGB) {
                    editor.updateTextProperty {
                        $0.stroke.color = CodableColor(
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
