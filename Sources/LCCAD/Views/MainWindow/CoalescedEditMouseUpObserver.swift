import AppKit
import SwiftUI

// MARK: - Coalesced edit mouse-up observer
//
// アプリ内でマウスボタンを離したら、まとめ中の連続編集を終える (#72)。
// SwiftUI の ColorPicker はドラッグの終了を通知しないため、NSEvent のローカルモニターで
// マウスアップを拾い、「1 回のドラッグ / 1 回のクリック = Undo 1 件」に区切る。
// ローカルモニターはイベントの配送前に呼ばれる。カラーパネルがマウスアップの処理中に送る
// 最後の値変更までを同じ Undo に含めるため、区切りはイベント処理の後(次の MainActor の
// 周回)まで遅らせる。

struct CoalescedEditMouseUpObserver: ViewModifier {
    let editor: EditorViewModel
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak editor] event in
                    Task { @MainActor in editor?.endCoalescedEdit() }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
