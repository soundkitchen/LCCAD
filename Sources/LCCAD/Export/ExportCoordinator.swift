import AppKit
import UniformTypeIdentifiers

@MainActor
enum ExportCoordinator {
    static func exportSVG(document: DocumentData) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .plainText]
        panel.nameFieldStringValue = "Untitled.svg"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let svg = SVGExporter.export(document: document)
                try svg.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    static func exportDXF(document: DocumentData, options: DXFExportOptions = .init()) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dxf") ?? .plainText]
        panel.nameFieldStringValue = "Untitled.dxf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let dxf = DXFExporter.export(document: document, options: options)
                try dxf.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
