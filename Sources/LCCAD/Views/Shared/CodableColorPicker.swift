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
// 上書きしない)。編集対象がすでにその色(誤差の範囲)なら onChange に渡さない。
// 元の色を返すのは、Undo で色を戻したときのためでもある。カラーパネルが返す色は sRGB とは
// 限らない(汎用 RGB など)ので、sRGB に変換した保存値をそのまま戻すと、見た目は同じでも
// パネルの明度などの表示が変わってしまう(明度 100% の色が 97.8% になる、など)。
//
// 送り返しは値だけでは見分けられない(複数選択で、先頭の図形と同じ色をユーザーが選んだ場合と
// 区別できない)。そこで「直前にピッカーへ渡した色と同じ値」が「カラーパネルでの操作以外」
// (選択変更のクリックや ⌘Z の処理中)に届いたものを送り返しとして捨てる。複数選択で色が
// ばらばらだと、送り返しを適用すると全図形が先頭の色に塗り替えられてしまうため (review #74)。

struct CodableColorPicker: View {
    /// ピッカーに表示する色(複数選択では先頭の図形の色)
    let color: CodableColor
    /// 編集対象の現在の色。変更が届いた時点で読む(body を組み立てたときの値は、
    /// 再描画の前に続けて変更が届くと古くなっている)。複数選択では選択中の全図形の色
    let currentColors: () -> [CodableColor]
    let onChange: (CodableColor) -> Void

    /// 直前にピッカーへ渡した色。描画のたびに更新するだけで再描画は起こさないので、参照型で持つ
    @State private var lastPushed = LastPushedColor()

    var body: some View {
        ColorPicker("", selection: selection)
            .labelsHidden()
    }

    private var selection: Binding<Color> {
        Binding(
            get: {
                lastPushed.color = color
                return ColorPickerHistory.shared.originalColor(for: color)
                    ?? Color(red: color.r, green: color.g, blue: color.b, opacity: color.a)
            },
            set: { newColor in
                guard let codable = CodableColor(newColor) else { return }
                guard !Self.isEcho(codable, lastPushed: lastPushed.color, event: NSApp.currentEvent) else { return }
                ColorPickerHistory.shared.record(newColor, as: codable)
                guard Self.shouldApply(codable, to: currentColors()) else { return }
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
        // ドラッグ中は直前と同じ色の更新が続くことが多いので、末尾だけ見て済ませる
        if let last = entries.last, last.codable.isApproximatelyEqual(to: codable) {
            entries[entries.count - 1] = (codable, color)
            return
        }
        entries.removeAll { $0.codable.isApproximatelyEqual(to: codable) }
        entries.append((codable, color))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// 保存値に対応する元の色。覚えていなければ nil。新しいものから探すので、
    /// ドラッグ中や再描画(直前に記録した色を引く)では末尾で見つかる
    func originalColor(for codable: CodableColor) -> Color? {
        entries.last { $0.codable.isApproximatelyEqual(to: codable) }?.color
    }
}

/// CodableColorPicker が直前にピッカーへ渡した色
@MainActor
final class LastPushedColor {
    var color: CodableColor?
}

extension CodableColorPicker {
    /// パネルからの送り返しか。直前にピッカーへ渡した色と同じ値が、カラーパネルでの操作
    /// (マウス・キー)以外から届いたら送り返しとみなす
    static func isEcho(_ color: CodableColor, lastPushed: CodableColor?, event: NSEvent?) -> Bool {
        guard let lastPushed, color.isApproximatelyEqual(to: lastPushed) else { return false }
        return !(event?.window is NSColorPanel)
    }

    /// ピッカーから届いた色を編集対象に適用するか。編集対象がすべてすでにその色(誤差の範囲)なら、
    /// パネルからの送り返しとして扱わない。複数選択で一部の図形だけ色が違う場合は、
    /// 先頭の図形と同じ色でも適用する
    static func shouldApply(_ color: CodableColor, to currentColors: [CodableColor]) -> Bool {
        !currentColors.allSatisfy { $0.isApproximatelyEqual(to: color) }
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
