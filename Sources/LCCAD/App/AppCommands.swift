import SwiftUI

struct AppCommands: Commands {
    let fileDocument: LCCADFileDocument
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        // Replace default New Window
        CommandGroup(replacing: .newItem) {
            Button("New") {
                fileDocument.newDocumentGuarded()
            }
            .keyboardShortcut("n")
        }

        // Export commands live in FileCommands' .saveItem replacement group
        // (see Issue #11: mixing replacing/after on the same placement drops the
        // after-group, so Export must share the replacing group).

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

            Button("Show Page Frames") {
                editor?.document.settings.pageLayout.showPageFrames.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
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

        // Arrange menu — alignment & distribution
        CommandMenu("Arrange") {
            let hasMulti = editor?.isMultiSelection ?? false
            let hasThreeOrMore = (editor?.selectedShapeIds.count ?? 0) >= 3

            Button("Align Left") {
                editor?.alignSelectedShapes(.left)
            }
            .keyboardShortcut("[", modifiers: [.command, .control])
            .disabled(!hasMulti)

            Button("Align Right") {
                editor?.alignSelectedShapes(.right)
            }
            .keyboardShortcut("]", modifiers: [.command, .control])
            .disabled(!hasMulti)

            Button("Align Top") {
                editor?.alignSelectedShapes(.top)
            }
            .keyboardShortcut("[", modifiers: [.command, .option])
            .disabled(!hasMulti)

            Button("Align Bottom") {
                editor?.alignSelectedShapes(.bottom)
            }
            .keyboardShortcut("]", modifiers: [.command, .option])
            .disabled(!hasMulti)

            Divider()

            Button("Align Center Horizontally") {
                editor?.alignSelectedShapes(.centerH)
            }
            .disabled(!hasMulti)

            Button("Align Center Vertically") {
                editor?.alignSelectedShapes(.centerV)
            }
            .disabled(!hasMulti)

            Divider()

            Button("Distribute Horizontally") {
                editor?.distributeSelectedShapes(.horizontal)
            }
            .disabled(!hasThreeOrMore)

            Button("Distribute Vertically") {
                editor?.distributeSelectedShapes(.vertical)
            }
            .disabled(!hasThreeOrMore)

            Divider()

            let hasAnySelection = editor?.hasSelection ?? false

            Button("Mirror Horizontally") {
                editor?.mirrorSelectedShapes(.vertical, copy: false)
            }
            .keyboardShortcut("|", modifiers: [.command, .shift])
            .disabled(!hasAnySelection)

            Button("Mirror Vertically") {
                editor?.mirrorSelectedShapes(.horizontal, copy: false)
            }
            .keyboardShortcut("_", modifiers: [.command, .shift])
            .disabled(!hasAnySelection)

            Divider()

            Button("Mirror Right (Copy)") {
                editor?.mirrorSelectedShapes(.vertical, copy: true)
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(!hasAnySelection)

            Button("Mirror Down (Copy)") {
                editor?.mirrorSelectedShapes(.horizontal, copy: true)
            }
            .keyboardShortcut("m", modifiers: [.command, .control])
            .disabled(!hasAnySelection)

            Divider()

            Button("Array...") {
                editor?.showArraySheet = true
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .disabled(!hasAnySelection)

            Button("Bevel...") {
                editor?.showBevelSheet = true
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
            .disabled(!hasAnySelection)
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
            Button("Dimension Tool (D)") { editor?.selectTool(.dimensionLine) }
        }

        // Stitch menu
        CommandMenu("Stitch") {
            Button("Auto Stitch") {
                editor?.autoStitchSelectedShape()
            }

            Button("Stitch Simulator") {
                // Planned feature; not yet implemented.
            }
            .disabled(true)

            Divider()

            Button("Pricking Iron Settings...") {
                editor?.showPrickingIronSheet = true
            }
        }
    }
}
