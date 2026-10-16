import XCTest
import SwiftUI
import AppKit
@testable import LCCAD

/// 内容欄のテキストビューが自前の入力 Undo を登録しないこと (#72)。
/// TextEditor の中の NSTextView は allowsUndo = true で、document と同じ UndoManager に
/// 入力 Undo を登録し、ViewModel の Undo と二重になっていた
@MainActor
final class UndoFreeTextViewTests: XCTestCase {

    private struct Host: View {
        @State var text = "abc"
        var body: some View {
            UndoFreeTextView(text: $text).frame(width: 200, height: 80)
        }
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }

    func testTextViewDoesNotRegisterItsOwnUndo() throws {
        let host = NSHostingView(rootView: Host())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(findTextView(in: host))
        XCTAssertFalse(textView.allowsUndo, "The content field must leave undo to the view model")
        XCTAssertEqual(textView.string, "abc")
        XCTAssertFalse(textView.isRichText)
    }
}
