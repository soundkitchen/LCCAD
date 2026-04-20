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

                CanvasView(editor: editor)
                    .frame(minWidth: 400)

                RightPanelView(editor: editor)
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 340)
            }

            StatusBarView(editor: editor)
        }
        .onAppear {
            editor.fileDocument = fileDocument
            editor.undoManager = undoManager
        }
        .onChange(of: undoManager) { _, newValue in
            editor.undoManager = newValue
        }
        .onChange(of: fileDocument.data) { _, newData in
            // Sync when file is opened externally
            editor.document = newData
            editor.fileDocument = fileDocument
        }
        .focusedValue(\.editor, editor)
        .onDeleteCommand {
            editor.deleteSelectedShapes()
        }
        .sheet(isPresented: $editor.showPrickingIronSheet) {
            PrickingIronSheet(editor: editor)
        }
    }
}
