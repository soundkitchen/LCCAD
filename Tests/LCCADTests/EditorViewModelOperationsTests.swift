import XCTest
@testable import LCCAD

/// 画面に依存しない操作 (#78): 図形の追加・レイヤー操作・パネルなしの書き出し
@MainActor
final class EditorViewModelOperationsTests: XCTestCase {

    private func makeLine(_ x: CGFloat) -> AnyShape {
        .line(LineShape(start: CGPoint(x: x, y: 0), end: CGPoint(x: x + 10, y: 0)))
    }

    private func temporaryURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }

    // MARK: - 図形の追加

    func testAddShapeAppendsToActiveLayerWithUndo() {
        let editor = EditorViewModel(document: DocumentData(layers: [Layer(name: "L1"), Layer(name: "L2")]))
        let undo = UndoManager()
        editor.undoManager = undo
        editor.activeLayerIndex = 1

        let line = makeLine(0)
        editor.addShape(line)

        XCTAssertEqual(editor.document.layers[1].shapes.map(\.id), [line.id])
        XCTAssertTrue(editor.document.layers[0].shapes.isEmpty)

        undo.undo()
        XCTAssertTrue(editor.document.layers[1].shapes.isEmpty)
        undo.redo()
        XCTAssertEqual(editor.document.layers[1].shapes.map(\.id), [line.id])
    }

    func testAddShapesRegistersSingleUndo() {
        let editor = EditorViewModel(document: .empty())
        let undo = UndoManager()
        editor.undoManager = undo

        let shapes = [makeLine(0), makeLine(20), makeLine(40)]
        editor.addShapes(shapes)
        XCTAssertEqual(editor.document.layers[0].shapes.map(\.id), shapes.map(\.id))

        // 1 回の Undo で全部が消え、1 回の Redo で全部が戻る
        undo.undo()
        XCTAssertTrue(editor.document.layers[0].shapes.isEmpty)
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(editor.document.layers[0].shapes.map(\.id), shapes.map(\.id))
    }

    func testAddShapesWithEmptyArrayRegistersNoUndo() {
        let editor = EditorViewModel(document: .empty())
        let undo = UndoManager()
        editor.undoManager = undo

        editor.addShapes([])
        XCTAssertFalse(undo.canUndo)
    }

    // MARK: - レイヤー

    func testAddLayerAppendsAndActivates() {
        let editor = EditorViewModel(document: .empty())
        editor.addLayer()
        XCTAssertEqual(editor.document.layers.map(\.name), ["Layer 1", "Layer 2"])
        XCTAssertEqual(editor.activeLayerIndex, 1)
    }

    func testRemoveActiveLayerKeepsLastLayer() {
        let editor = EditorViewModel(document: .empty())
        editor.removeActiveLayer()
        XCTAssertEqual(editor.document.layers.count, 1)
    }

    func testRemoveActiveLayerClampsIndex() {
        let editor = EditorViewModel(document: DocumentData(layers: [Layer(name: "A"), Layer(name: "B")]))
        editor.activeLayerIndex = 1
        editor.removeActiveLayer()
        XCTAssertEqual(editor.document.layers.map(\.name), ["A"])
        XCTAssertEqual(editor.activeLayerIndex, 0)
    }

    func testMoveActiveLayerFollowsTheLayer() {
        let editor = EditorViewModel(document: DocumentData(layers: [Layer(name: "A"), Layer(name: "B"), Layer(name: "C")]))
        editor.activeLayerIndex = 1

        editor.moveActiveLayerUp()
        XCTAssertEqual(editor.document.layers.map(\.name), ["B", "A", "C"])
        XCTAssertEqual(editor.activeLayerIndex, 0)

        // 先頭ではそれ以上動かない
        editor.moveActiveLayerUp()
        XCTAssertEqual(editor.document.layers.map(\.name), ["B", "A", "C"])

        editor.activeLayerIndex = 1
        editor.moveActiveLayerDown()
        XCTAssertEqual(editor.document.layers.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(editor.activeLayerIndex, 2)

        // 末尾ではそれ以上動かない
        editor.moveActiveLayerDown()
        XCTAssertEqual(editor.document.layers.map(\.name), ["B", "C", "A"])
    }

    /// レイヤー追加(Undo なし)の後に、図形の追加を Undo してレイヤーが減ると、
    /// activeLayerIndex が範囲外のまま残る。その状態でもレイヤー操作が落ちない
    func testLayerOperationsTolerateStaleActiveLayerIndex() {
        let editor = EditorViewModel(document: .empty())
        let undo = UndoManager()
        editor.undoManager = undo
        editor.addShape(makeLine(0))
        editor.addLayer()
        XCTAssertEqual(editor.activeLayerIndex, 1)

        undo.undo()
        XCTAssertEqual(editor.document.layers.count, 1)
        XCTAssertEqual(editor.activeLayerIndex, 1, "前提: 添字が範囲外のまま残る")

        editor.moveActiveLayerUp()
        editor.moveActiveLayerDown()
        editor.removeActiveLayer()
        XCTAssertEqual(editor.document.layers.count, 1)
    }

    func testRemoveActiveLayerWithStaleIndexRemovesTheClampedLayer() {
        let editor = EditorViewModel(document: DocumentData(layers: [Layer(name: "A"), Layer(name: "B"), Layer(name: "C")]))
        editor.activeLayerIndex = 2
        // Undo などで、添字を残したままレイヤーが 2 枚に減った状態
        editor.document.layers.removeLast()

        editor.removeActiveLayer()
        XCTAssertEqual(editor.document.layers.map(\.name), ["A"])
        XCTAssertEqual(editor.activeLayerIndex, 0)
    }

    func testMoveActiveLayerUpWithStaleIndexMovesTheClampedLayer() {
        let editor = EditorViewModel(document: DocumentData(layers: [Layer(name: "A"), Layer(name: "B"), Layer(name: "C")]))
        editor.activeLayerIndex = 2
        editor.document.layers.removeLast()

        editor.moveActiveLayerUp()
        XCTAssertEqual(editor.document.layers.map(\.name), ["B", "A"])
        XCTAssertEqual(editor.activeLayerIndex, 0)
    }

    func testToggleLayerVisibility() {
        let editor = EditorViewModel(document: .empty())
        editor.toggleLayerVisibility(at: 0)
        XCTAssertFalse(editor.document.layers[0].isVisible)
        editor.toggleLayerVisibility(at: 0)
        XCTAssertTrue(editor.document.layers[0].isVisible)

        // 範囲外は無視する
        editor.toggleLayerVisibility(at: 5)
        XCTAssertTrue(editor.document.layers[0].isVisible)
    }

    // MARK: - 開く・新規

    /// 図形 1 本・レイヤー 1 枚のファイルを書き出す
    private func writeSampleFile() throws -> (url: URL, data: DocumentData) {
        let source = LCCADFileDocument()
        source.data.layers[0].name = "From file"
        source.data.layers[0].shapes = [makeLine(100)]
        let url = temporaryURL("lccad")
        try source.write(to: url)
        return (url, source.data)
    }

    /// 編集中の状態(図形・選択・別レイヤー・Undo 履歴)を持つエディタ
    private func makeEditedEditor(fileDocument: LCCADFileDocument, undo: UndoManager) -> EditorViewModel {
        let editor = EditorViewModel(document: fileDocument.data)
        editor.fileDocument = fileDocument
        editor.undoManager = undo
        editor.addLayer()
        let line = makeLine(0)
        editor.addShape(line)
        editor.selectedShapeIds = [line.id]
        return editor
    }

    func testOpenDocumentAdoptsLoadedDocumentImmediately() throws {
        let (url, loaded) = try writeSampleFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let fileDocument = LCCADFileDocument()
        let undo = UndoManager()
        let editor = makeEditedEditor(fileDocument: fileDocument, undo: undo)

        try editor.openDocument(at: url)

        XCTAssertEqual(editor.document, loaded)
        XCTAssertEqual(fileDocument.data, loaded)
        XCTAssertEqual(editor.activeLayerIndex, 0)
        XCTAssertTrue(editor.selectedShapeIds.isEmpty)
        XCTAssertFalse(undo.canUndo, "破棄した document に ⌘Z で戻れない")
        XCTAssertFalse(fileDocument.isModified)
    }

    /// 開いた直後の編集が、読み込んだ内容に積み上がる(古い document が書き戻されない)。
    /// 後からキャンバスが loadGeneration の変化で呼んでも、その編集は消えない
    func testEditRightAfterOpenBuildsOnLoadedDocument() throws {
        let (url, loaded) = try writeSampleFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let fileDocument = LCCADFileDocument()
        let undo = UndoManager()
        let editor = makeEditedEditor(fileDocument: fileDocument, undo: undo)

        try editor.openDocument(at: url)
        let added = makeLine(200)
        editor.addShape(added)
        editor.adoptLoadedDocumentIfNeeded()

        let expectedIds = loaded.layers[0].shapes.map(\.id) + [added.id]
        XCTAssertEqual(fileDocument.data.layers[0].shapes.map(\.id), expectedIds)
        XCTAssertEqual(editor.document, fileDocument.data)
        XCTAssertTrue(undo.canUndo, "開いた後の編集の Undo は残る")
    }

    func testOpenDocumentFailureKeepsEditorState() throws {
        let fileDocument = LCCADFileDocument()
        let undo = UndoManager()
        let editor = makeEditedEditor(fileDocument: fileDocument, undo: undo)
        let before = editor.document
        let selection = editor.selectedShapeIds

        XCTAssertThrowsError(try editor.openDocument(at: temporaryURL("lccad")))
        XCTAssertEqual(editor.document, before)
        XCTAssertEqual(editor.selectedShapeIds, selection)
        XCTAssertTrue(undo.canUndo)
    }

    func testNewDocumentAdoptsEmptyDocument() throws {
        let fileDocument = LCCADFileDocument()
        let undo = UndoManager()
        let editor = makeEditedEditor(fileDocument: fileDocument, undo: undo)

        try editor.newDocument()

        XCTAssertEqual(editor.document.layers.count, 1)
        XCTAssertTrue(editor.document.layers[0].shapes.isEmpty)
        XCTAssertEqual(editor.document, fileDocument.data)
        XCTAssertEqual(editor.activeLayerIndex, 0)
        XCTAssertTrue(editor.selectedShapeIds.isEmpty)
        XCTAssertFalse(undo.canUndo)
    }

    /// メニューの開く・新規の経路: LCCADFileDocument 側で置き換え、キャンバスが後から呼ぶ
    func testAdoptAfterFileDocumentReplacementResetsEditor() throws {
        let (url, loaded) = try writeSampleFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let fileDocument = LCCADFileDocument()
        let undo = UndoManager()
        let editor = makeEditedEditor(fileDocument: fileDocument, undo: undo)

        try fileDocument.read(from: url)
        editor.adoptLoadedDocumentIfNeeded()

        XCTAssertEqual(editor.document, loaded)
        XCTAssertTrue(editor.selectedShapeIds.isEmpty)
        XCTAssertFalse(undo.canUndo)
    }

    func testFileOperationsWithoutFileDocumentThrow() {
        let editor = EditorViewModel(document: .empty())
        XCTAssertThrowsError(try editor.openDocument(at: temporaryURL("lccad"))) {
            XCTAssertEqual($0 as? EditorOperationError, .noFileDocument)
        }
        XCTAssertThrowsError(try editor.newDocument()) {
            XCTAssertEqual($0 as? EditorOperationError, .noFileDocument)
        }
    }

    // MARK: - ページ

    func testPageMoveRegistersSingleUndo() {
        let editor = EditorViewModel(document: .empty())
        editor.addPage(at: CGPoint(x: 0, y: 0))
        let undo = UndoManager()
        editor.undoManager = undo

        editor.beginPageMove()
        XCTAssertEqual(editor.pageDragRawOrigin, CGPoint(x: 0, y: 0))
        editor.setSelectedPageOrigin(CGPoint(x: 10, y: 0))
        editor.setSelectedPageOrigin(CGPoint(x: 20, y: 5))
        editor.commitPageMove()
        XCTAssertNil(editor.pageDragRawOrigin)
        XCTAssertNil(editor.pageMoveUndoSnapshot)

        let origin = { editor.document.settings.pageLayout.pages.first?.origin }
        XCTAssertEqual(origin(), CGPoint(x: 20, y: 5))
        undo.undo()
        XCTAssertEqual(origin(), CGPoint(x: 0, y: 0))
        XCTAssertFalse(undo.canUndo, "ドラッグ全体で Undo 1 件")
    }

    func testBeginPageMoveWithoutSelectionDoesNothing() {
        let editor = EditorViewModel(document: .empty())
        editor.beginPageMove()
        XCTAssertNil(editor.pageMoveUndoSnapshot)
        XCTAssertNil(editor.pageDragRawOrigin)
    }

    func testSetSelectedPageOriginMovesOnlyTheSelectedPage() {
        let editor = EditorViewModel(document: .empty())
        editor.addPage(at: CGPoint(x: 0, y: 0))
        let first = editor.selectedPageId
        editor.addPage(at: CGPoint(x: 500, y: 0))

        editor.setSelectedPageOrigin(CGPoint(x: 600, y: 30))

        let pages = editor.document.settings.pageLayout.pages
        XCTAssertEqual(pages.first { $0.id == first }?.origin, CGPoint(x: 0, y: 0))
        XCTAssertEqual(pages.first { $0.id == editor.selectedPageId }?.origin, CGPoint(x: 600, y: 30))
    }

    func testSetSelectedPageOriginWithoutSelectionDoesNothing() {
        let editor = EditorViewModel(document: .empty())
        editor.addPage(at: CGPoint(x: 10, y: 10))
        editor.selectedPageId = nil
        let before = editor.document

        editor.setSelectedPageOrigin(CGPoint(x: 99, y: 99))
        XCTAssertEqual(editor.document, before)
    }

    // MARK: - 書き出し

    func testExportSVGToURLWritesExporterOutput() throws {
        let editor = EditorViewModel(document: .empty())
        editor.addShape(makeLine(0))
        let url = temporaryURL("svg")
        defer { try? FileManager.default.removeItem(at: url) }

        try editor.exportSVG(to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8),
                       SVGExporter.export(document: editor.document))
    }

    func testExportDXFToURLWritesExporterOutput() throws {
        let editor = EditorViewModel(document: .empty())
        editor.addShape(makeLine(0))
        let url = temporaryURL("dxf")
        defer { try? FileManager.default.removeItem(at: url) }

        try editor.exportDXF(to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8),
                       DXFExporter.export(document: editor.document))
    }
}
