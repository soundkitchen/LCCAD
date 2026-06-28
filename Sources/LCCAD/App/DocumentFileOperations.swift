import AppKit
import SwiftUI

// MARK: - Unsaved-changes guard & file operations
//
// Centralizes Save / Save As / Open / New plus the "you have unsaved changes"
// confirmation used by ⌘Q, window close, New and Open (Issue #22).
// These are native NSAlert / NSSavePanel / NSOpenPanel flows, so they live in
// the App layer rather than the model.

extension LCCADFileDocument {

    /// User's choice in the unsaved-changes confirmation dialog.
    enum SaveConfirmationChoice {
        case save
        case dontSave
        case cancel
    }

    // MARK: Low-level write

    /// Encode and write `data` to `url`, then update `fileURL` and the saved baseline.
    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        try encoded.write(to: url, options: .atomic)
        fileURL = url
        markSaved()
    }

    // MARK: Save / Save As

    /// Save to the existing file, or fall back to a Save As panel when untitled.
    /// `completion(true)` indicates the document was written to disk.
    func saveOrPresentPanel(completion: @escaping (Bool) -> Void = { _ in }) {
        if let url = fileURL {
            do {
                try write(to: url)
                completion(true)
            } catch {
                NSAlert(error: error).runModal()
                completion(false)
            }
        } else {
            presentSaveAsPanel(completion: completion)
        }
    }

    /// Always prompt for a destination, regardless of the current `fileURL`.
    func presentSaveAsPanel(completion: @escaping (Bool) -> Void = { _ in }) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.lccad]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.lccad"
        panel.begin { [weak self] response in
            guard let self else { completion(false); return }
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            do {
                try self.write(to: url)
                completion(true)
            } catch {
                NSAlert(error: error).runModal()
                completion(false)
            }
        }
    }

    // MARK: Open / New (guarded entry points)

    /// New document, guarding any unsaved changes first.
    func newDocumentGuarded() {
        guardUnsavedChanges { [weak self] in
            guard let self else { return }
            self.data = .empty()
            self.fileURL = nil
            self.markSaved()
        }
    }

    /// Open from disk, guarding any unsaved changes first.
    func openDocumentGuarded() {
        guardUnsavedChanges { [weak self] in
            self?.presentOpenPanel()
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.lccad, .json]
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                let raw = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(DocumentData.self, from: raw)
                self.data = decoded
                self.fileURL = url
                self.markSaved()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    // MARK: Confirmation dialog

    /// Present the standard three-button save dialog when there are unsaved
    /// changes. Returns the user's choice; returns `.dontSave` immediately when
    /// the document is clean (nothing to lose).
    func confirmUnsavedChanges() -> SaveConfirmationChoice {
        guard isModified else { return .dontSave }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to this document?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")          // .alertFirstButtonReturn
        alert.addButton(withTitle: "Cancel")        // .alertSecondButtonReturn
        alert.addButton(withTitle: "Don't Save")    // .alertThirdButtonReturn

        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .save
        case .alertThirdButtonReturn:  return .dontSave
        default:                       return .cancel
        }
    }

    /// Run the unsaved-changes guard, then perform `proceed` only if it is safe
    /// to discard the current document (clean, saved, or "Don't Save").
    /// Used by New and Open.
    func guardUnsavedChanges(proceed: @escaping () -> Void) {
        switch confirmUnsavedChanges() {
        case .dontSave:
            proceed()
        case .cancel:
            break
        case .save:
            saveOrPresentPanel { saved in
                if saved { proceed() }
            }
        }
    }

    // MARK: App termination (⌘Q)

    /// Reply for `applicationShouldTerminate(_:)`.
    /// When a Save As panel is needed the reply is deferred via `.terminateLater`
    /// and resolved through `NSApp.reply(toApplicationShouldTerminate:)`.
    func terminationReply() -> NSApplication.TerminateReply {
        switch confirmUnsavedChanges() {
        case .dontSave:
            return .terminateNow
        case .cancel:
            return .terminateCancel
        case .save:
            if let url = fileURL {
                do {
                    try write(to: url)
                    return .terminateNow
                } catch {
                    NSAlert(error: error).runModal()
                    return .terminateCancel
                }
            } else {
                presentSaveAsPanel { saved in
                    NSApp.reply(toApplicationShouldTerminate: saved)
                }
                return .terminateLater
            }
        }
    }

    // MARK: Window close (⌘W / red ×)

    /// Decide whether a window may close. When a Save As panel is needed the
    /// window is kept open and closed programmatically once the save succeeds.
    func windowShouldClose(_ window: NSWindow) -> Bool {
        switch confirmUnsavedChanges() {
        case .dontSave:
            return true
        case .cancel:
            return false
        case .save:
            if let url = fileURL {
                do {
                    try write(to: url)
                    return true
                } catch {
                    NSAlert(error: error).runModal()
                    return false
                }
            } else {
                presentSaveAsPanel { [weak window] saved in
                    if saved { window?.close() }
                }
                return false
            }
        }
    }
}
