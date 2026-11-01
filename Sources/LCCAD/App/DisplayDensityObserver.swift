import AppKit
import SwiftUI

// MARK: - Display density observer
//
// ウィンドウのあるディスプレイの物理密度（pt/mm）を EditorViewModel に供給する (#62)。
// これにより「ズーム 100% = 画面上の 1mm が実物の 1mm」が成立する。
// 再計算・再供給のトリガーは 2 つ（% 表記の基準が変わるだけで、見た目の scale は維持される）:
//  • NSWindow.didChangeScreenNotification — ウィンドウが別ディスプレイへ移動したとき
//  • NSApplication.didChangeScreenParametersNotification — 同一ディスプレイのまま
//    スケーリング（解像度）が変わったときや、attach 時点で screen 未確定だった場合の
//    後追い (review #64)

struct DisplayDensityObserver: NSViewRepresentable {
    let editor: EditorViewModel

    func makeNSView(context: Context) -> NSView {
        let view = ScreenTrackingView()
        view.onScreenChange = { [weak editor] screen in
            // ディスプレイが未確定(attach 直後など)なら、後追いの通知を待つ
            guard let editor, let screen else { return }
            if let pointsPerMm = DisplayDensityObserver.pointsPerMillimeter(of: screen),
               EditorViewModel.plausibleDensityRange.contains(pointsPerMm) {
                editor.updateDisplayBaseline(pointsPerMm: pointsPerMm)
            } else {
                // ディスプレイは分かったが密度が取れない。フォールバックの基準で確定させる (review #100)
                editor.markDisplayDensityUnavailable()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// ディスプレイの論理解像度（pt）と物理サイズ（mm）から pt/mm を算出する。
    /// 物理サイズが取得できないディスプレイ（一部の仮想ディスプレイ等）では nil
    static func pointsPerMillimeter(of screen: NSScreen) -> CGFloat? {
        guard let screenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }

        let physicalSize = CGDisplayScreenSize(CGDirectDisplayID(screenNumber.uint32Value))
        guard physicalSize.width > 0 else { return nil }
        return screen.frame.width / physicalSize.width
    }

    // MARK: - Screen tracking view

    private final class ScreenTrackingView: NSView {
        var onScreenChange: ((NSScreen?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(
                self, name: NSWindow.didChangeScreenNotification, object: nil)
            NotificationCenter.default.removeObserver(
                self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(screenChanged),
                name: NSWindow.didChangeScreenNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(screenChanged),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
            onScreenChange?(window.screen)
        }

        @objc private func screenChanged(_ notification: Notification) {
            onScreenChange?(window?.screen)
        }
    }
}
