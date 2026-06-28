import AppKit
import SwiftUI

// MARK: - Window configurator
//
// Bridges the document's dirty state to the hosting NSWindow:
//  • intercepts the window close button / ⌘W via `windowShouldClose` (Issue #22)
//  • keeps the title-bar "edited" dot (`isDocumentEdited`) in sync with `isModified`
//
// The close interception installs a proxy NSWindowDelegate that forwards every
// other delegate callback to SwiftUI's own delegate, so window behavior
// (full-screen, restoration, etc.) is preserved.

struct WindowConfigurator: NSViewRepresentable {
    @ObservedObject var fileDocument: LCCADFileDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(fileDocument: fileDocument)
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowTrackingView()
        view.onMoveToWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-assert the delegate (SwiftUI may reinstall its own) and refresh the dot.
        let window = nsView.window
        context.coordinator.attach(to: window)
        window?.isDocumentEdited = fileDocument.isModified
    }

    // MARK: Coordinator (proxy window delegate)

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private let fileDocument: LCCADFileDocument
        // weak by design: `NSWindow.delegate` is itself a weak reference, so we must
        // not strongly retain SwiftUI's delegate (it would outlive the window /
        // create a cycle). `attach(to:)` re-runs from `updateNSView`, re-capturing
        // SwiftUI's delegate if it is ever reinstalled.
        private weak var previousDelegate: NSWindowDelegate?

        init(fileDocument: LCCADFileDocument) {
            self.fileDocument = fileDocument
        }

        func attach(to window: NSWindow?) {
            guard let window, window.delegate !== self else { return }
            previousDelegate = window.delegate
            window.delegate = self
            window.isDocumentEdited = fileDocument.isModified
        }

        // MARK: NSWindowDelegate

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            // The unsaved-changes guard owns the close decision. We deliberately do
            // not also consult the original delegate's `windowShouldClose`: once the
            // guard has saved (and cleared the dirty state), a veto there would leave
            // a "saved but won't close" window. SwiftUI's teardown runs via
            // `windowWillClose`, which is still forwarded below.
            fileDocument.windowShouldClose(sender)
        }

        // Forward every callback we don't implement to SwiftUI's delegate.

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return previousDelegate?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if previousDelegate?.responds(to: aSelector) == true {
                return previousDelegate
            }
            return super.forwardingTarget(for: aSelector)
        }
    }
}

// MARK: - NSView that reports window attachment

private final class WindowTrackingView: NSView {
    var onMoveToWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onMoveToWindow?(window)
    }
}
