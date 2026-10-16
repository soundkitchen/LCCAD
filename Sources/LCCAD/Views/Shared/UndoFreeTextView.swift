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
//
// 未確定文字(IME の変換中の文字)は document に書き込まず、確定したときに書き込む。
// 打鍵以外の編集(ペースト・カット・メニューからの操作など)は前後で連続入力のまとめを区切り、
// 独立した Undo にする(一般的なテキストエディタと同じ)。

struct UndoFreeTextView: NSViewRepresentable {
    @Binding var text: String
    /// 編集対象の識別子(図形 id)。変わったら未確定文字を捨てて、新しい対象の値を表示する
    var identity: AnyHashable
    var fontSize: CGFloat = 11
    /// 連続入力のまとめを区切るときに呼ばれる(フォーカスアウト、打鍵以外の編集の前後)
    var onEditBoundary: () -> Void = {}

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
        context.coordinator.identity = identity
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if coordinator.identity != identity {
            // 変換の途中で別の図形に切り替わった。未確定文字を確定させると新しい図形に
            // 書き込まれてしまうので捨てる
            coordinator.identity = identity
            coordinator.isApplyingExternalText = true
            if textView.hasMarkedText() {
                textView.inputContext?.discardMarkedText()
            }
            textView.string = text
            coordinator.isApplyingExternalText = false
            return
        }
        // IME の変換中は書き戻さない(未確定文字が消えるのを防ぐ)
        guard !textView.hasMarkedText() else { return }
        // Undo/Redo などで外から値が変わったときに追従する
        if textView.string != text {
            coordinator.isApplyingExternalText = true
            textView.string = text
            coordinator.isApplyingExternalText = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: UndoFreeTextView
        var identity: AnyHashable?
        /// 外からの値をテキストビューに反映している最中(その変更は書き戻さない)
        var isApplyingExternalText = false

        init(_ parent: UndoFreeTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText,
                  let textView = notification.object as? NSTextView,
                  // 未確定文字は書き込まない。確定(または取り消し)したときに改めて届く
                  !textView.hasMarkedText() else { return }
            let isTyping = Self.isTypingEvent(NSApp.currentEvent)
            if !isTyping { parent.onEditBoundary() }
            parent.text = textView.string
            if !isTyping { parent.onEditBoundary() }
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEditBoundary()
        }

        /// 打鍵による編集か。⌘ / ⌃ 付きのキー(⌘V など)やマウス・メニューからの操作は打鍵ではない
        static func isTypingEvent(_ event: NSEvent?) -> Bool {
            guard let event, event.type == .keyDown else { return false }
            return event.modifierFlags.intersection([.command, .control]).isEmpty
        }
    }
}
