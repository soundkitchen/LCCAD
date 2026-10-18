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
        .background(DisplayDensityObserver(editor: editor))
        .modifier(CoalescedEditBoundaryObserver(editor: editor))
        .onAppear {
            editor.fileDocument = fileDocument
            editor.undoManager = undoManager
            // エージェント用の MCP Server が操作する対象 (#79)
            MCPServerController.shared.editor = editor
        }
        .onChange(of: undoManager) { _, newValue in
            editor.undoManager = newValue
        }
        .onChange(of: fileDocument.loadGeneration) { _, _ in
            // メニューの開く・新規で document が丸ごと置き換わったら、エディタの状態を
            // 合わせる(Issue #22 review)。操作の層から開いた場合は合わせ済みなので何もしない (#78)
            editor.adoptLoadedDocumentIfNeeded()
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
        .sheet(isPresented: $editor.showBevelSheet) {
            BevelSheet(editor: editor)
        }
        .sheet(isPresented: $editor.showBoxStitchSheet, onDismiss: {
            // Covers Apply, Cancel, the xmark button, and Esc uniformly.
            editor.boxStitchPreview = nil
        }) {
            BoxStitchSheet(editor: editor)
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
