import AppKit
import SwiftUI

// MARK: - Undo-free text view
//
// 複数行のテキスト入力欄。テキスト図形の内容欄で使う (#72)。
// SwiftUI の TextEditor は、中の NSTextView が自前の入力 Undo をウィンドウの UndoManager
// (= document の UndoManager)に登録する。そのため ViewModel の Undo と二重になり、⌘Z が
// 両方を別々に戻してしまう。さらに NSTextView の Undo はテキストビュー自身の文字列を戻すので、
// 選択を変えた後に ⌘Z すると、別の図形に戻した文字列が書き込まれるおそれがある。
// allowsUndo を切った NSTextView を使い、Undo は ViewModel 側(連続入力を 1 件にまとめる)に
// 一本化する。⌘Z はレスポンダーチェーンでウィンドウの UndoManager に届き、ViewModel の Undo が
// 戻した document が updateNSView でこの欄に反映される。

struct UndoFreeTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 11
    /// 編集が終わった(フォーカスが外れた)ときに呼ばれる
    var onEndEditing: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        // 背景・枠は SwiftUI 側(TextSection)で描く
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        if let textView = scrollView.documentView as? NSTextView {
            textView.allowsUndo = false
            textView.isRichText = false
            textView.importsGraphics = false
            textView.drawsBackground = false
            textView.font = .systemFont(ofSize: fontSize)
            textView.textColor = .labelColor
            textView.string = text
            textView.delegate = context.coordinator
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // IME の変換中は書き戻さない(未確定文字列が消えるのを防ぐ)
        guard !textView.hasMarkedText() else { return }
        // Undo/Redo や選択変更で外から値が変わったときに追従する
        if textView.string != text {
            textView.string = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: UndoFreeTextView

        init(_ parent: UndoFreeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }
    }
}
