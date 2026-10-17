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
            UndoFreeTextView(text: $text, identity: 0).frame(width: 200, height: 80)
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

    // MARK: - 打鍵かどうかの判定

    private func keyEvent(_ characters: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                         windowNumber: 0, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)
    }

    func testPlainKeyIsTyping() {
        XCTAssertTrue(UndoFreeTextView.Coordinator.isTypingEvent(keyEvent("a")))
        XCTAssertTrue(UndoFreeTextView.Coordinator.isTypingEvent(keyEvent("A", modifiers: .shift)))
        XCTAssertTrue(UndoFreeTextView.Coordinator.isTypingEvent(keyEvent("å", modifiers: .option)))
    }

    func testCommandOrControlKeyIsNotTyping() {
        // ⌘V / ⌘X などは独立した Undo にする
        XCTAssertFalse(UndoFreeTextView.Coordinator.isTypingEvent(keyEvent("v", modifiers: .command)))
        XCTAssertFalse(UndoFreeTextView.Coordinator.isTypingEvent(keyEvent("k", modifiers: .control)))
    }

    func testNonKeyEventIsNotTyping() {
        // メニュー・右クリックなど、キー入力以外から来た編集
        XCTAssertFalse(UndoFreeTextView.Coordinator.isTypingEvent(nil))
        let mouse = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        XCTAssertFalse(UndoFreeTextView.Coordinator.isTypingEvent(mouse))
    }

    // MARK: - 連続編集の区切りになるイベント

    func testMouseDownsAreEditBoundaries() throws {
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: 0, context: nil, eventNumber: 0,
                                                         clickCount: 1, pressure: 1))
            XCTAssertTrue(CoalescedEditBoundaryObserver.isEditBoundary(event), "\(type)")
        }
    }

    func testKeyDownOutsideColorPanelIsNotEditBoundary() throws {
        // 内容欄の打鍵(メインウィンドウでのキー入力)ではまとめを区切らない
        let event = try XCTUnwrap(keyEvent("a"))
        XCTAssertFalse(CoalescedEditBoundaryObserver.isEditBoundary(event))
    }
}
