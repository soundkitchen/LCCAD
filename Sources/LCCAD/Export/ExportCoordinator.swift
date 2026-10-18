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
                try writeSVG(document: document, to: url)
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
                try writeDXF(document: document, options: options, to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    // MARK: - パネルなしの書き出し (#78)

    /// SVG を `url` に書き出す。パネル経由の書き出しもここを通る
    static func writeSVG(document: DocumentData, to url: URL) throws {
        let svg = SVGExporter.export(document: document)
        try svg.write(to: url, atomically: true, encoding: .utf8)
    }

    /// DXF を `url` に書き出す。パネル経由の書き出しもここを通る
    static func writeDXF(document: DocumentData, options: DXFExportOptions = .init(), to url: URL) throws {
        let dxf = DXFExporter.export(document: document, options: options)
        try dxf.write(to: url, atomically: true, encoding: .utf8)
    }
}
