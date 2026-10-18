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

    // MARK: - ページ

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
