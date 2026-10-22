import AppKit
import SwiftUI

// MARK: - Coalesced edit boundary observer
//
// 操作の区切りで、まとめ中の連続編集を終える (#72)。
// カラーウェル(`NSColorWell`)はドラッグの終了を通知しないため、NSEvent のローカルモニターで
// 操作の区切りを拾い、「1 回のドラッグ / 1 回のクリック / 1 回のキー確定 = Undo 1 件」にする。
// ウェルのポップオーバーもアプリのウィンドウなので、色見本のクリックも 1 回ごとに区切られる。
//
// - マウスダウン(左・右・その他): 新しいマウス操作の始まり。マウスアップではなくマウスダウンで
//   区切るのは、カラーパネルのホイールやスウォッチがマウスの追跡を自前のループで行って
//   マウスアップを消費し、ローカルモニターに届かないため。マウスダウンは追跡が始まる前に
//   配送されるので、ここで同期的に区切れば、その操作で届く値の変更はすべて新しい Undo 1 件に
//   まとまる。右クリックも区切るので、コンテキストメニューからの編集は直前の入力に混ざらない
// - カラーパネルでのキー入力: 16 進欄の Enter やスライダーのキー操作で確定した色を、
//   1 回ごとに別の Undo にする。内容欄の打鍵(メインウィンドウでのキー入力)は区切らない

struct CoalescedEditBoundaryObserver: ViewModifier {
    let editor: EditorViewModel
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
                ) { [weak editor] event in
                    if Self.isEditBoundary(event) {
                        // ローカルモニターはメインスレッドで呼ばれる
                        MainActor.assumeIsolated { editor?.endCoalescedEdit() }
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    /// 連続編集の区切りになるイベントか
    static func isEditBoundary(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        case .keyDown:
            return event.window is NSColorPanel
        default:
            return false
        }
    }
}
