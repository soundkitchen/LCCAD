import SwiftUI

struct AppCommands: Commands {
    let fileDocument: LCCADFileDocument
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        // Replace default New Window
        CommandGroup(replacing: .newItem) {
            Button("New") {
                fileDocument.data = .empty()
            }
            .keyboardShortcut("n")
        }

        // Export commands
        CommandGroup(after: .saveItem) {
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

        // View menu — append to system View menu
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Zoom In") {
                editor?.zoomIn()
            }
            .keyboardShortcut("+")

            Button("Zoom Out") {
                editor?.zoomOut()
            }
            .keyboardShortcut("-")

            Button("Zoom to Fit") {
                editor?.zoomToFit()
            }
            .keyboardShortcut("0")

            Divider()

            Button("Toggle Grid") {
                editor?.document.settings.showGrid.toggle()
            }
            .keyboardShortcut("g", modifiers: [.command, .option])

            Button("Toggle Ruler") {
                editor?.document.settings.showRuler.toggle()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        // Edit menu — Select All
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Select All") {
                editor?.selectAll()
            }
            .keyboardShortcut("a")

            Button("Deselect All") {
                editor?.selectedShapeIds = []
            }
            .keyboardShortcut("d")

            Divider()

            Button("Group") {
                editor?.groupSelectedShapes()
            }
            .keyboardShortcut("g")
            .disabled(!(editor?.isMultiSelection ?? false))

            Button("Ungroup") {
                editor?.ungroupSelectedShapes()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!(editor?.hasSelectedGroup ?? false))
        }

        // Draw menu — tool switching (shortcuts are single-key, handled via onKeyPress in CanvasView)
        CommandMenu("Draw") {
            Button("Select Tool (V)") { editor?.selectTool(.select) }
            Button("Line Tool (L)") { editor?.selectTool(.line) }
            Button("Rectangle Tool (R)") { editor?.selectTool(.rectangle) }
            Button("Ellipse Tool (E)") { editor?.selectTool(.ellipse) }
            Button("Arc Tool (A)") { editor?.selectTool(.arc) }
            Button("Bezier Tool (P)") { editor?.selectTool(.bezier) }
            Button("Text Tool (T)") { editor?.selectTool(.text) }
        }

        // Stitch menu
        CommandMenu("Stitch") {
            Button("Auto Stitch") {
                editor?.autoStitchSelectedShape()
            }

            Button("Stitch Simulator") {
                // TODO: not yet implemented
            }

            Divider()

            Button("Pricking Iron Settings...") {
                editor?.showPrickingIronSheet = true
            }
        }
    }
}
