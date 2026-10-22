import AppKit
import SwiftUI

// MARK: - Codable color picker
//
// CodableColor を編集するカラーウェル (#72)。
// クリックすると、色の四角のすぐそばにポップオーバーで色見本を出す(`NSColorWell` の
// `.minimal` スタイル)。細かい指定は、ポップオーバーから全部入りのカラーパネルを開いて行う。
// SwiftUI の `ColorPicker` はクリックで直接カラーパネルを開き、パネルは前回の位置
// (クリックした場所から離れていることが多い)に出るので、`NSColorWell` を直接使う。
//
// ウェルに色を渡し直すのは、保存値がウェルの色と誤差(Float 精度)の範囲を超えて違うときだけ
// (Undo・選択の切り替えなど)。document が更新されて再描画されるたびに誤差を含んだ色を
// 渡し直すと、開いているカラーパネルの色が上書きされ、ホイールの指示点がマウス位置から飛ぶ
// (白・灰色に近い色では、わずかな誤差で色相が大きく変わる)。
// 渡し直すときは、ピッカーから届いた色を「保存値 → 元の色」の対応で覚えておき
// (`ColorPickerHistory`)、元の色をそのまま渡す。カラーパネルが返す色は sRGB とは限らない
// (汎用 RGB など)ので、sRGB に変換した保存値を渡すと、見た目は同じでもパネルの明度などの
// 表示が変わってしまう(明度 100% の色が 97.8% になる、など)。
//
// `NSColorWell` は、コードから色を変えたときには action を送らない(ユーザーがポップオーバー・
// パネル・ドロップで色を変えたときだけ送る)。そのため、渡し直した色が送り返されることはない。
// 編集対象がすでにその色(誤差の範囲)なら onChange に渡さない(意図しない Undo を積まない)。

struct CodableColorPicker: NSViewRepresentable {
    /// ウェルに表示する色(複数選択では先頭の図形の色)
    let color: CodableColor
    /// 編集対象の現在の色。変更が届いた時点で読む(ビューを組み立てたときの値は、
    /// 再描画の前に続けて変更が届くと古くなっている)。複数選択では選択中の全図形の色
    let currentColors: () -> [CodableColor]
    let onChange: (CodableColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(style: .minimal)
        well.supportsAlpha = true
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorDidChange(_:))
        well.color = Self.colorToPush(for: color)
        well.isEnabled = context.environment.isEnabled
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.parent = self
        well.isEnabled = context.environment.isEnabled
        if let newColor = Self.colorToShow(for: color, showing: well.color) {
            well.color = newColor
        }
    }

    /// 取り除くウェルを、共有のカラーパネルから切り離す。選択が変わると右パネルのセクションが
    /// 作り直されるので、パネルを開いたままだと、パネルが取り除いたウェル(古い選択の onChange)を
    /// 指したまま残る(review #92)
    static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) {
        well.deactivate()
    }

    /// ウェルが描く枠(色見本と、ポップオーバーを示す印)の大きさのまま置く。
    /// 置き場所いっぱいに広げない
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSColorWell, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: CodableColorPicker

        init(parent: CodableColorPicker) {
            self.parent = parent
        }

        @objc func colorDidChange(_ sender: NSColorWell) {
            guard let codable = CodableColor(sender.color) else {
                // sRGB にできない色(画像のパレットのパターンなど)は使えないので、
                // ウェルの表示をすぐに保存値の色へ戻す(次の再描画まで食い違ったままにしない)
                sender.color = CodableColorPicker.colorToPush(for: parent.color)
                return
            }
            ColorPickerHistory.shared.record(sender.color, as: codable)
            guard CodableColorPicker.shouldApply(codable, to: parent.currentColors()) else { return }
            parent.onChange(codable)
        }
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
    private var entries: [(codable: CodableColor, color: NSColor)] = []

    init(capacity: Int = 256) {
        self.capacity = capacity
    }

    func record(_ color: NSColor, as codable: CodableColor) {
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
    func originalColor(for codable: CodableColor) -> NSColor? {
        entries.last { $0.codable.isApproximatelyEqual(to: codable) }?.color
    }
}

extension CodableColorPicker {
    /// ウェルに渡し直す色。ウェルが表示中の色(`showing`)と保存値が誤差の範囲で同じなら nil
    /// (渡し直さない)
    @MainActor
    static func colorToShow(for color: CodableColor, showing current: NSColor,
                            history: ColorPickerHistory = .shared) -> NSColor? {
        if let shown = CodableColor(current), shown.isApproximatelyEqual(to: color) {
            return nil
        }
        return colorToPush(for: color, history: history)
    }

    /// 保存値をウェルに渡すときの色。覚えている元の色があればそれを、なければ sRGB の色を返す
    @MainActor
    static func colorToPush(for color: CodableColor, history: ColorPickerHistory = .shared) -> NSColor {
        history.originalColor(for: color)
            ?? NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a)
    }

    /// ピッカーから届いた色を編集対象に適用するか。編集対象がすべてすでにその色(誤差の範囲)なら
    /// 適用しない(何も変わらない Undo を積まない)。複数選択で一部の図形だけ色が違う場合は、
    /// 先頭の図形と同じ色でも適用する
    static func shouldApply(_ color: CodableColor, to currentColors: [CodableColor]) -> Bool {
        !currentColors.allSatisfy { $0.isApproximatelyEqual(to: color) }
    }
}

extension CodableColor {
    /// NSColor から作る。描画・印刷は成分を sRGB として扱う
    /// (`Color(red:green:blue:)` / `NSColor(red:green:blue:alpha:)`)ので、sRGB に変換して取り出す
    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(r: srgb.redComponent, g: srgb.greenComponent,
                  b: srgb.blueComponent, a: srgb.alphaComponent)
    }

    /// 変換誤差の範囲で同じ色か。許容差は 8bit の 1 階調(1/255)より十分小さくとる
    func isApproximatelyEqual(to other: CodableColor, tolerance: CGFloat = 1e-4) -> Bool {
        abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance
            && abs(b - other.b) <= tolerance && abs(a - other.a) <= tolerance
    }
}
