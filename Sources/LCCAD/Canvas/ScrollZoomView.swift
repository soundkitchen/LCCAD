import SwiftUI
import AppKit

/// An invisible NSView overlay that captures scroll wheel events for zoom
/// and passes them to the EditorViewModel.
struct ScrollZoomModifier: ViewModifier {
    @Bindable var editor: EditorViewModel

    func body(content: Content) -> some View {
        content.overlay {
            ScrollZoomRepresentable(editor: editor)
        }
    }
}

struct ScrollZoomRepresentable: NSViewRepresentable {
    var editor: EditorViewModel

    func makeNSView(context: Context) -> ScrollZoomNSView {
        let view = ScrollZoomNSView()
        view.editor = editor
        return view
    }

    func updateNSView(_ nsView: ScrollZoomNSView, context: Context) {
        nsView.editor = editor
    }
}

class ScrollZoomNSView: NSView {
    var editor: EditorViewModel?

    override func scrollWheel(with event: NSEvent) {
        guard let editor else { return }

        if event.modifierFlags.contains(.command) || event.phase == .changed || event.momentumPhase == .changed {
            // ⌘+scroll or trackpad pinch → zoom
            let zoomDelta = event.scrollingDeltaY
            guard abs(zoomDelta) > 0.01 else { return }

            let factor: CGFloat = 1 + zoomDelta * 0.01
            let mouseLocation = convert(event.locationInWindow, from: nil)
            let flippedY = bounds.height - mouseLocation.y
            let center = CGPoint(x: mouseLocation.x, y: flippedY)

            Task { @MainActor in
                editor.transform.zoom(by: factor, center: center)
            }
        } else {
            // Normal scroll → pan
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            Task { @MainActor in
                editor.transform.pan(by: CGPoint(x: dx, y: -dy))
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

extension View {
    func scrollZoom(editor: EditorViewModel) -> some View {
        modifier(ScrollZoomModifier(editor: editor))
    }
}
