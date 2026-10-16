import AppKit
import SwiftUI

// MARK: - Codable color picker
//
// CodableColor を編集する ColorPicker (#72)。
// 素の ColorPicker に CodableColor との変換バインディングを渡すと、document が更新されて
// ビューが再描画されるたびに、変換誤差(Float 精度)を含んだ色がピッカーに渡し直され、
// 開いているカラーパネルの色が上書きされる。その結果、ホイールの指示点がマウス位置から
// 飛び(白・灰色に近い色では、わずかな誤差で色相が大きく変わる)、パネルが誤差の分だけ
// 違う色を送り返して、意図しない Undo が積まれる。
// そこで、ユーザーが選んだ色をそのまま覚えておき、保存値と誤差の範囲で同じならその色を
// ピッカーに返す(パネルを上書きしない)。誤差の範囲の変更は onChange に渡さない。

struct CodableColorPicker: View {
    let color: CodableColor
    let onChange: (CodableColor) -> Void

    /// 直近にピッカーから届いた色と、それを CodableColor に変換したもの
    @State private var picked: (color: Color, codable: CodableColor)?

    var body: some View {
        ColorPicker("", selection: selection)
            .labelsHidden()
    }

    private var selection: Binding<Color> {
        Binding(
            get: {
                if let picked, picked.codable.isApproximatelyEqual(to: color) {
                    return picked.color
                }
                return Color(red: color.r, green: color.g, blue: color.b, opacity: color.a)
            },
            set: { newColor in
                guard let codable = CodableColor(newColor) else { return }
                picked = (newColor, codable)
                // パネルからの送り返し(誤差だけの変化)は変更として扱わない
                guard !codable.isApproximatelyEqual(to: color) else { return }
                onChange(codable)
            }
        )
    }
}

extension CodableColor {
    /// SwiftUI の Color から作る。描画・印刷は成分を sRGB として扱う
    /// (`Color(red:green:blue:)` / `NSColor(red:green:blue:alpha:)`)ので、sRGB に変換して取り出す
    init?(_ color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(r: srgb.redComponent, g: srgb.greenComponent,
                  b: srgb.blueComponent, a: srgb.alphaComponent)
    }

    /// 変換誤差の範囲で同じ色か。許容差は 8bit の 1 階調(1/255)より十分小さくとる
    func isApproximatelyEqual(to other: CodableColor, tolerance: CGFloat = 1e-4) -> Bool {
        abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance
            && abs(b - other.b) <= tolerance && abs(a - other.a) <= tolerance
    }
}
