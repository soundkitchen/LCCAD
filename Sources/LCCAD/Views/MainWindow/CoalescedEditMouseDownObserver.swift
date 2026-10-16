import AppKit
import SwiftUI

// MARK: - Coalesced edit mouse-down observer
//
// アプリ内でマウスボタンを押したら、まとめ中の連続編集を終える (#72)。
// SwiftUI の ColorPicker はドラッグの終了を通知しないため、NSEvent のローカルモニターで
// マウス操作の区切りを拾い、「1 回のドラッグ / 1 回のクリック = Undo 1 件」にする。
// マウスアップではなくマウスダウンで区切るのは、カラーパネルのホイールやスウォッチが
// マウスの追跡を自前のループで行ってマウスアップを消費し、ローカルモニターに届かないため。
// マウスダウンは追跡が始まる前に配送されるので、ここで同期的に区切れば、その操作で
// 送られてくる値の変更はすべて新しい Undo 1 件にまとまる。

struct CoalescedEditMouseDownObserver: ViewModifier {
    let editor: EditorViewModel
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak editor] event in
                    // ローカルモニターはメインスレッドで呼ばれる
                    MainActor.assumeIsolated { editor?.endCoalescedEdit() }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
