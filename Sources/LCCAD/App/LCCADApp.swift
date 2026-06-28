import SwiftUI

@main
struct LCCADApp: App {
    @State private var fileDocument = LCCADFileDocument()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            MainEditorView(fileDocument: fileDocument)
                .onAppear {
                    AppearanceMode(rawValue: appearanceMode)?.apply()
                    appDelegate.fileDocument = fileDocument
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

/// Intercepts ⌘Q so unsaved changes can be guarded (Issue #22).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The single shared document, injected from `LCCADApp` once the window appears.
    weak var fileDocument: LCCADFileDocument?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let fileDocument else { return .terminateNow }
        // AppKit calls this on the main thread.
        return MainActor.assumeIsolated { fileDocument.terminationReply() }
    }
}

/// File menu commands for manual Save/Open/Print
struct FileCommands: Commands {
    let fileDocument: LCCADFileDocument

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                fileDocument.saveOrPresentPanel()
            }
            .keyboardShortcut("s")

            Button("Save As...") {
                fileDocument.presentSaveAsPanel()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("Open...") {
                fileDocument.openDocumentGuarded()
            }
            .keyboardShortcut("o")

            Divider()

            Menu("Export") {
                Button("SVG...") {
                    ExportCoordinator.exportSVG(document: fileDocument.data)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("DXF...") {
                    ExportCoordinator.exportDXF(document: fileDocument.data)
                }
            }
        }

        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                printDocument()
            }
            .keyboardShortcut("p")

            Button("Print Calibration Page...") {
                PrintCoordinator.printCalibrationPage(from: NSApp.keyWindow)
            }
        }
    }

    @MainActor
    private func printDocument() {
        let store = PrinterCalibrationStore.shared

        // Check if the currently selected printer has a calibration
        let printInfo = NSPrintInfo.shared
        let printerName = printInfo.printer.name
        let hasCalibration = store.calibration(forPrinter: printerName) != nil

        if !hasCalibration {
            let alert = NSAlert()
            alert.messageText = "Printer Not Calibrated"
            alert.informativeText = "The printer \"\(printerName)\" has no calibration profile. Prints may not be physically accurate. You can calibrate in Settings > Printer Calibration."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Print Anyway")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
        }

        PrintCoordinator.printDocument(fileDocument.data, from: NSApp.keyWindow)
    }
}
