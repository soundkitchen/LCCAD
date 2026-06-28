import SwiftUI

struct MainEditorView: View {
    @ObservedObject var fileDocument: LCCADFileDocument
    @State private var editor: EditorViewModel
    @Environment(\.undoManager) private var undoManager

    init(fileDocument: LCCADFileDocument) {
        self._fileDocument = ObservedObject(wrappedValue: fileDocument)
        self._editor = State(initialValue: EditorViewModel(document: fileDocument.data))
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(editor: editor)

            HSplitView {
                LeftPanelView(editor: editor)
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 320)

                canvasWithRuler
                    .frame(minWidth: 400)

                RightPanelView(editor: editor)
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 340)
            }

            StatusBarView(editor: editor)
        }
        .background(WindowConfigurator(fileDocument: fileDocument))
        .onAppear {
            editor.fileDocument = fileDocument
            editor.undoManager = undoManager
        }
        .onChange(of: undoManager) { _, newValue in
            editor.undoManager = newValue
        }
        .onChange(of: fileDocument.loadGeneration) { _, _ in
            // A New/Open load wholesale-replaced the document: adopt it and reset
            // editor state that referenced the old document (Issue #22 review).
            editor.document = fileDocument.data
            editor.fileDocument = fileDocument
            editor.activeLayerIndex = min(max(editor.activeLayerIndex, 0),
                                          max(fileDocument.data.layers.count - 1, 0))
            editor.selectedShapeIds = []
            // Drop undo history so ⌘Z can't resurrect the discarded document.
            editor.undoManager?.removeAllActions()
        }
        .focusedValue(\.editor, editor)
        .onDeleteCommand {
            editor.deleteSelectedShapes()
        }
        .sheet(isPresented: $editor.showPrickingIronSheet) {
            PrickingIronSheet(editor: editor)
        }
        .sheet(isPresented: $editor.showArraySheet) {
            ArraySheet(editor: editor)
        }
        .sheet(isPresented: $editor.showSaveTemplateSheet) {
            SaveTemplateSheet(editor: editor)
        }
    }

    // MARK: - Canvas with Ruler

    @ViewBuilder
    private var canvasWithRuler: some View {
        VStack(spacing: 0) {
            if editor.document.settings.showRuler {
                HStack(spacing: 0) {
                    RulerCornerView()
                    HorizontalRulerView(editor: editor)
                }
            }
            HStack(spacing: 0) {
                if editor.document.settings.showRuler {
                    VerticalRulerView(editor: editor)
                }
                CanvasView(editor: editor)
            }
        }
    }
}
