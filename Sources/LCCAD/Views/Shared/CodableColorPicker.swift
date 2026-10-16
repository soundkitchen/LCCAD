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
// そこで、ピッカーから届いた色を「保存値 → 元の色」の対応で覚えておき(`ColorPickerHistory`)、
// 保存値が覚えている色と誤差の範囲で同じなら、元の色をそのままピッカーに返す(パネルを
// 上書きしない)。誤差の範囲の変更は onChange に渡さない。
// 元の色を返すのは、Undo で色を戻したときのためでもある。カラーパネルが返す色は sRGB とは
// 限らない(汎用 RGB など)ので、sRGB に変換した保存値をそのまま戻すと、見た目は同じでも
// パネルの明度などの表示が変わってしまう(明度 100% の色が 97.8% になる、など)。

struct CodableColorPicker: View {
    let color: CodableColor
    let onChange: (CodableColor) -> Void

    var body: some View {
        ColorPicker("", selection: selection)
            .labelsHidden()
    }

    private var selection: Binding<Color> {
        Binding(
            get: {
                ColorPickerHistory.shared.originalColor(for: color)
                    ?? Color(red: color.r, green: color.g, blue: color.b, opacity: color.a)
            },
            set: { newColor in
                guard let codable = CodableColor(newColor) else { return }
                ColorPickerHistory.shared.record(newColor, as: codable)
                // パネルからの送り返し(誤差だけの変化)は変更として扱わない
                guard !codable.isApproximatelyEqual(to: color) else { return }
                onChange(codable)
            }
        )
    }
}

/// カラーピッカーから届いた色と、それを保存値(CodableColor)に変換したものの対応。
/// アプリの起動中だけ覚えておく(保存形式は変えない)。右パネルのセクションは選択が変わると
/// 作り直されるので、ビューの State ではなくアプリ全体で 1 つ持つ
@MainActor
final class ColorPickerHistory {
    static let shared = ColorPickerHistory()

    /// 覚えておく件数の上限。ドラッグ中は更新のたびに記録されるので、
    /// 何回か前のクリックまで Undo で戻っても見つかるよう多めにとる
    let capacity: Int

    /// 新しいものが末尾
    private var entries: [(codable: CodableColor, color: Color)] = []

    init(capacity: Int = 256) {
        self.capacity = capacity
    }

    func record(_ color: Color, as codable: CodableColor) {
        entries.removeAll { $0.codable.isApproximatelyEqual(to: codable) }
        entries.append((codable, color))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// 保存値に対応する元の色。覚えていなければ nil
    func originalColor(for codable: CodableColor) -> Color? {
        entries.last { $0.codable.isApproximatelyEqual(to: codable) }?.color
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
