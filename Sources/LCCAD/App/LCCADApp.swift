import SwiftUI

@main
struct LCCADApp: App {
    @State private var fileDocument = LCCADFileDocument()
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            MainEditorView(fileDocument: fileDocument)
                .onAppear {
                    AppearanceMode(rawValue: appearanceMode)?.apply()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            AppCommands(fileDocument: fileDocument)
            FileCommands(fileDocument: fileDocument)
        }

        Settings {
            SettingsView()
        }
    }
}

/// File menu commands for manual Save/Open
struct FileCommands: Commands {
    let fileDocument: LCCADFileDocument

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                saveDocument()
            }
            .keyboardShortcut("s")

            Button("Save As...") {
                saveDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("Open...") {
                openDocument()
            }
            .keyboardShortcut("o")
        }
    }

    @MainActor
    private func saveToURL(_ url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(fileDocument.data)
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    private func saveDocument() {
        if let url = fileDocument.fileURL {
            do {
                try saveToURL(url)
            } catch {
                NSAlert(error: error).runModal()
            }
        } else {
            saveDocumentAs()
        }
    }

    @MainActor
    private func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.lccad]
        panel.nameFieldStringValue = fileDocument.fileURL?.lastPathComponent ?? "Untitled.lccad"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try saveToURL(url)
                fileDocument.fileURL = url
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @MainActor
    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.lccad, .json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(DocumentData.self, from: data)
                fileDocument.data = decoded
                fileDocument.fileURL = url
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
