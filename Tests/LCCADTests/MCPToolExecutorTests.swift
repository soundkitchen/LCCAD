import XCTest
import MCP
@testable import LCCAD

/// MCP のツールの実行 (#79)
@MainActor
final class MCPToolExecutorTests: XCTestCase {

    private var fileDocument: LCCADFileDocument!
    private var editor: EditorViewModel!
    private var undo: UndoManager!
    private var executor: MCPToolExecutor { MCPToolExecutor(editor: editor) }

    override func setUp() async throws {
        fileDocument = LCCADFileDocument()
        editor = EditorViewModel(document: fileDocument.data)
        editor.fileDocument = fileDocument
        undo = UndoManager()
        editor.undoManager = undo
    }

    private func temporaryURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }

    @discardableResult
    private func call(_ name: String, _ arguments: [String: Value] = [:],
                      file: StaticString = #filePath, line: UInt = #line) -> CallTool.Result {
        executor.call(name, arguments: arguments)
    }

    private func text(_ result: CallTool.Result) -> String {
        for content in result.content {
            if case .text(let text, _, _) = content { return text }
        }
        return ""
    }

    private func json(_ result: CallTool.Result) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text(result).utf8)) as? [String: Any])
    }

    private func assertSucceeded(_ result: CallTool.Result, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(result.isError, true, text(result), file: file, line: line)
    }

    private func assertFailed(_ result: CallTool.Result, containing message: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.isError, true, file: file, line: line)
        XCTAssertTrue(text(result).contains(message), "\(text(result))", file: file, line: line)
    }

    private let twoLines: Value = .array([
        ["type": "line", "start": [0, 0], "end": [10, 0]],
        ["type": "line", "start": [0, 10], "end": [10, 10]],
    ])

    /// 線を 2 本足して id を返す
    private func addTwoLines() throws -> [String] {
        let result = call("add_shapes", ["shapes": twoLines])
        assertSucceeded(result)
        return try XCTUnwrap(json(result)["ids"] as? [String])
    }

    // MARK: - 一覧

    func testCatalogNamesAreUniqueAndAllHandled() {
        let names = MCPToolCatalog.tools.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        for name in names {
            XCTAssertFalse(text(call(name)).hasPrefix("Unknown tool"), name)
        }
        assertFailed(call("no_such_tool"), containing: "Unknown tool")
    }

    // MARK: - 図形

    func testAddShapesInOneUndoStep() throws {
        let ids = try addTwoLines()
        XCTAssertEqual(editor.document.layers[0].shapes.map(\.id.uuidString), ids)
        XCTAssertEqual(fileDocument.data, editor.document)

        undo.undo()
        XCTAssertTrue(editor.document.layers[0].shapes.isEmpty)
        XCTAssertFalse(undo.canUndo)
    }

    func testAddShapesToAnotherLayerKeepsActiveLayer() throws {
        editor.addLayer()
        editor.activeLayerIndex = 1
        assertSucceeded(call("add_shapes", ["shapes": twoLines, "layer_index": 0]))
        XCTAssertEqual(editor.document.layers[0].shapes.count, 2)
        XCTAssertTrue(editor.document.layers[1].shapes.isEmpty)
        XCTAssertEqual(editor.activeLayerIndex, 1)

        assertFailed(call("add_shapes", ["shapes": twoLines, "layer_index": 5]), containing: "out of range")
    }

    func testAddShapesReportsWhichShapeIsInvalid() {
        let shapes: Value = .array([
            ["type": "line", "start": [0, 0], "end": [10, 0]],
            ["type": "polyline", "points": [[0, 0]]],
        ])
        let result = call("add_shapes", ["shapes": shapes])
        assertFailed(result, containing: "Invalid arguments")
        XCTAssertTrue(text(result).contains("shapes.[1]"), text(result))
        XCTAssertTrue(editor.document.layers[0].shapes.isEmpty, "1 つでも不正なら何も追加しない")
    }

    func testDeleteShapesKeepsOtherSelection() throws {
        let ids = try addTwoLines()
        editor.selectedShapeIds = [UUID(uuidString: ids[1])!]

        assertSucceeded(call("delete_shapes", ["ids": [.string(ids[0])]]))
        XCTAssertEqual(editor.document.layers[0].shapes.map(\.id.uuidString), [ids[1]])
        XCTAssertEqual(editor.selectedShapeIds, [UUID(uuidString: ids[1])!])
    }

    func testDuplicateIdsAreCountedOnce() throws {
        let ids = try addTwoLines()
        let result = call("delete_shapes", ["ids": [.string(ids[0]), .string(ids[0])]])
        assertSucceeded(result)
        XCTAssertEqual(try json(result)["deleted"] as? Int, 1)
        XCTAssertEqual(editor.document.layers[0].shapes.count, 1)
    }

    /// ドラッグの途中は document を変えるツールを断り、読み取りだけのツールは通す(review #86)
    func testToolsThatChangeTheDocumentWaitForTheGesture() throws {
        let ids = try addTwoLines()
        editor.moveUndoSnapshot = editor.document

        assertFailed(call("add_shapes", ["shapes": twoLines]), containing: "dragging")
        assertFailed(call("delete_shapes", ["ids": [.string(ids[0])]]), containing: "dragging")
        assertFailed(call("rename_layer", ["layer_index": 0, "name": "A"]), containing: "dragging")
        assertFailed(call("save_document", ["path": .string(temporaryURL("lccad").path)]), containing: "dragging")
        assertSucceeded(call("get_document"))
        assertSucceeded(call("render_image", ["width": 200]))
        XCTAssertEqual(editor.document.layers[0].shapes.count, 2)

        editor.moveUndoSnapshot = nil
        assertSucceeded(call("add_shapes", ["shapes": twoLines]))
        XCTAssertEqual(editor.document.layers[0].shapes.count, 4)
    }

    func testUnknownIdsAreRejected() throws {
        _ = try addTwoLines()
        let unknown = UUID().uuidString
        assertFailed(call("delete_shapes", ["ids": [.string(unknown)]]), containing: unknown)
        assertFailed(call("move_shapes", ["ids": ["not-a-uuid"], "dx": 1, "dy": 1]), containing: "Unknown shape ids")
        XCTAssertEqual(editor.document.layers[0].shapes.count, 2)
    }

    func testMoveShapesWithUndo() throws {
        // テスト環境では UndoManager の自動グループが閉じず、追加と移動が 1 件にまとまってしまう。
        // 図形は Undo を通さずに用意し、移動の Undo だけを確かめる
        let line = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))
        editor.document.layers[0].shapes = [.line(line)]
        let ids = [line.id.uuidString]
        assertSucceeded(call("move_shapes", ["ids": [.string(ids[0])], "dx": 5, "dy": -2]))
        guard case .line(let moved) = editor.document.layers[0].shapes[0] else { return XCTFail("not a line") }
        XCTAssertEqual(moved.startPoint, CGPoint(x: 5, y: -2))
        XCTAssertTrue(editor.selectedShapeIds.isEmpty, "元の選択(なし)に戻る")

        undo.undo()
        guard case .line(let restored) = editor.document.layers[0].shapes[0] else { return XCTFail("not a line") }
        XCTAssertEqual(restored.startPoint, CGPoint(x: 0, y: 0))
    }

    func testSetStroke() throws {
        let ids = try addTwoLines()
        assertSucceeded(call("set_stroke", ["ids": .array(ids.map { .string($0) }), "color": "#FF0000", "line_style": "dotted"]))
        for shape in editor.document.layers[0].shapes {
            XCTAssertEqual(shape.stroke.color, CodableColor(r: 1, g: 0, b: 0))
            XCTAssertEqual(shape.stroke.lineStyle, .dotted)
            XCTAssertEqual(shape.stroke.dashPattern, LineStyle.dotted.dashPattern)
        }
        assertFailed(call("set_stroke", ["ids": [.string(ids[0])]]), containing: "color and/or line_style")
        assertFailed(call("set_stroke", ["ids": [.string(ids[0])], "color": "blue"]), containing: "Invalid color")
    }

    func testSetTextOnlyOnTextShapes() throws {
        let added = call("add_shapes", ["shapes": [["type": "text", "position": [0, 0], "content": "A"]]])
        let textId = try XCTUnwrap(json(added)["ids"] as? [String])[0]
        assertSucceeded(call("set_text", ["id": .string(textId), "content": "Card", "font_size": 9]))
        guard case .text(let text) = editor.document.layers[0].shapes[0] else { return XCTFail("not a text") }
        XCTAssertEqual(text.content, "Card")
        XCTAssertEqual(text.fontSize, 9)

        let lineId = try addTwoLines()[0]
        assertFailed(call("set_text", ["id": .string(lineId), "content": "X"]), containing: "not a text shape")
    }

    func testSelectShapes() throws {
        let ids = try addTwoLines()
        assertSucceeded(call("select_shapes", ["ids": .array(ids.map { .string($0) })]))
        XCTAssertEqual(editor.selectedShapeIds, Set(ids.compactMap(UUID.init(uuidString:))))
        assertSucceeded(call("select_shapes", ["ids": []]))
        XCTAssertTrue(editor.selectedShapeIds.isEmpty)
    }

    // MARK: - レイヤー (#95)

    func testRenameLayerWithUndo() throws {
        // addLayer() も Undo を積み、同じイベントのグループにまとまるので、Undo を通さずに足す
        editor.document.layers.append(Layer(name: "Layer 2"))
        editor.activeLayerIndex = 1
        let result = call("rename_layer", ["layer_index": 0, "name": "  裁断線 "])
        assertSucceeded(result)
        XCTAssertEqual(try json(result)["name"] as? String, "裁断線", "前後の空白を除いた名前を返す")
        XCTAssertEqual(editor.document.layers.map(\.name), ["裁断線", "Layer 2"])
        XCTAssertEqual(editor.activeLayerIndex, 1, "アクティブレイヤーは変えない")
        XCTAssertEqual(undo.undoActionName, "Rename Layer")

        undo.undo()
        XCTAssertEqual(editor.document.layers.map(\.name), ["Layer 1", "Layer 2"])
    }

    func testRenameLayerRejectsEmptyNameAndOutOfRange() {
        assertFailed(call("rename_layer", ["layer_index": 0, "name": " \n "]), containing: "must not be empty")
        assertFailed(call("rename_layer", ["layer_index": 1, "name": "A"]), containing: "out of range")
        assertFailed(call("rename_layer", ["layer_index": -1, "name": "A"]), containing: "out of range")
        assertFailed(call("rename_layer", ["name": "A"]), containing: "Invalid arguments")
        XCTAssertEqual(editor.document.layers.map(\.name), ["Layer 1"])
        XCTAssertFalse(undo.canUndo)
    }

    // MARK: - Undo

    func testUndoAndRedo() throws {
        assertFailed(call("undo"), containing: "Nothing to undo")
        _ = try addTwoLines()

        let undone = try json(call("undo"))
        XCTAssertEqual(undone["undone"] as? String, "Add Shapes")
        XCTAssertEqual(undone["can_redo"] as? Bool, true)
        XCTAssertTrue(editor.document.layers[0].shapes.isEmpty)

        assertSucceeded(call("redo"))
        XCTAssertEqual(editor.document.layers[0].shapes.count, 2)
        assertFailed(call("redo"), containing: "Nothing to redo")
    }

    // MARK: - 表示 (#81)

    /// キャンバスの大きさ 800×600、100% = 4 pt/mm で、起動時の実寸 100% の適用を済ませる
    private func makeViewReady() {
        editor.canvasSize = CGSize(width: 800, height: 600)
        editor.updateDisplayBaseline(pointsPerMm: 4.0)
        XCTAssertTrue(editor.isViewReady)
    }

    func testGetViewReturnsViewState() throws {
        makeViewReady()
        editor.setViewForTesting(scale: 8.0, offset: CGPoint(x: 400, y: 300))

        let view = try json(call("get_view"))

        XCTAssertEqual(view["zoom_percent"] as? Int, 200)
        // 0.5〜50 pt/mm を 4 pt/mm で割った範囲
        XCTAssertEqual(view["zoom_percent_range"] as? [Double], [12.5, 1250])
        XCTAssertEqual(view["points_per_mm"] as? Double, 8.0)
        XCTAssertEqual(view["baseline_points_per_mm"] as? Double, 4.0)
        XCTAssertEqual(view["offset_pt"] as? [Double], [400, 300])
        XCTAssertEqual(view["canvas_size_pt"] as? [Double], [800, 600])
        let visible = try XCTUnwrap(view["visible_rect_mm"] as? [String: Double])
        XCTAssertEqual(visible, ["x": -50, "y": -37.5, "width": 100, "height": 75])
    }

    func testSetViewAppliesResetZoomCenterAndPanInOrder() throws {
        makeViewReady()
        editor.setViewForTesting(scale: 1.0, offset: CGPoint(x: -123, y: 456))

        let result = call("set_view", [
            "reset": "actual_size", "zoom_percent": 300, "center": [10, 20], "pan_by": [3.7, -1.5],
        ])

        assertSucceeded(result)
        XCTAssertEqual(editor.transform.scale, 12.0, accuracy: 1e-9)
        // (10, 20) を中央に置いてから、図面を右へ 3.7pt・上へ 1.5pt ずらす
        let screen = editor.transform.worldToScreen(CGPoint(x: 10, y: 20))
        XCTAssertEqual(screen.x, 403.7, accuracy: 1e-9)
        XCTAssertEqual(screen.y, 298.5, accuracy: 1e-9)
        // 結果は変えたあとの表示状態
        XCTAssertEqual(try json(result)["zoom_percent"] as? Int, 300)
        // 表示の変更は document も Undo も変えない
        XCTAssertFalse(undo.canUndo)
        XCTAssertEqual(fileDocument.isModified, false)
    }

    func testSetViewFitShowsShapes() throws {
        makeViewReady()
        try addTwoLines()

        assertSucceeded(call("set_view", ["reset": "fit"]))

        let visible = editor.visibleWorldRect
        XCTAssertTrue(visible.contains(CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    func testSetViewClampsZoomToTheReportedRange() throws {
        makeViewReady()

        let view = try json(call("set_view", ["zoom_percent": 5000]))

        XCTAssertEqual(view["zoom_percent"] as? Int, 1250)
        XCTAssertEqual(editor.transform.scale, CanvasTransform.maxScale, accuracy: 1e-9)
    }

    func testSetViewRejectsInvalidArgumentsWithoutChangingTheView() {
        makeViewReady()
        editor.setViewForTesting(scale: 5.0, offset: CGPoint(x: 10, y: 20))

        assertFailed(call("set_view"), containing: "Pass at least one")
        assertFailed(call("set_view", ["zoom_percent": 0]), containing: "zoom_percent")
        assertFailed(call("set_view", ["reset": "actual_size", "center": [1]]), containing: "center")
        assertFailed(call("set_view", ["reset": "actual_size", "pan_by": [1, .double(.nan)]]), containing: "pan_by")
        assertFailed(call("set_view", ["reset": "zoom_in"]), containing: "Invalid arguments")

        XCTAssertEqual(editor.transform.scale, 5.0)
        XCTAssertEqual(editor.transform.offset, CGPoint(x: 10, y: 20))
    }

    /// 有限でも極端に大きい座標を見せる表示にはせず、元の表示に戻す(review #100)
    func testSetViewRejectsViewsBeyondTheCoordinateLimit() throws {
        makeViewReady()
        let before = editor.transform

        assertFailed(call("set_view", ["reset": "actual_size", "center": [1e308, 0]]), containing: "left unchanged")
        assertFailed(call("set_view", ["center": [2_000_000, 0]]), containing: "left unchanged")
        assertFailed(call("set_view", ["pan_by": [0, 1e12]]), containing: "left unchanged")

        XCTAssertEqual(editor.transform.scale, before.scale)
        XCTAssertEqual(editor.transform.offset, before.offset)
        assertSucceeded(call("set_view", ["center": [900_000, -900_000]]))
    }

    /// 範囲のチェックで失敗した set_view は、起動時の表示のままかも元に戻す。そのあと
    /// ウィンドウが大きくなったら、原点を中央に置き直す (#101 review)
    func testFailedSetViewKeepsRecenteringOnResize() {
        makeViewReady()

        assertFailed(call("set_view", ["center": [2_000_000, 0]]), containing: "left unchanged")
        editor.canvasSize = CGSize(width: 1600, height: 1200)

        XCTAssertEqual(editor.transform.offset, CGPoint(x: 800, y: 600))
    }

    /// 起動時の実寸 100% の適用が済むまでは、表示の値が仮のもので、変えても後で上書きされる(review #100)
    func testViewToolsWaitUntilTheViewIsReady() throws {
        XCTAssertFalse(editor.isViewReady)
        assertFailed(call("get_view"), containing: "not ready")
        assertFailed(call("set_view", ["zoom_percent": 200]), containing: "not ready")

        editor.canvasSize = CGSize(width: 800, height: 600)
        assertFailed(call("get_view"), containing: "not ready")

        editor.updateDisplayBaseline(pointsPerMm: 4.0)
        assertSucceeded(call("get_view"))
        assertSucceeded(call("set_view", ["zoom_percent": 200]))
    }

    /// 密度が取れない環境(仮想ディスプレイなど)でも、表示のツールがいつまでも断られない(review #100)
    func testViewToolsWorkWhenDisplayDensityIsUnavailable() throws {
        editor.canvasSize = CGSize(width: 800, height: 600)
        assertFailed(call("get_view"), containing: "not ready")

        editor.markDisplayDensityUnavailable()

        let view = try json(call("get_view"))
        XCTAssertEqual(view["baseline_points_per_mm"] as? Double, Double(CanvasTransform.fallbackBaselineScale))
        assertSucceeded(call("set_view", ["zoom_percent": 200]))
    }

    /// ドラッグの途中は表示を変えない(画面とワールド座標の対応が変わるとドラッグが崩れるため)
    func testSetViewWaitsForTheGestureButGetViewDoesNot() throws {
        makeViewReady()
        editor.moveUndoSnapshot = editor.document
        let scale = editor.transform.scale

        assertFailed(call("set_view", ["zoom_percent": 200]), containing: "dragging")
        assertSucceeded(call("get_view"))
        XCTAssertEqual(editor.transform.scale, scale)
    }

    /// マーキー選択は始点を画面座標で持つので、途中で表示を変えると別の図形が選ばれる(review #100)
    func testSetViewWaitsForTheMarquee() throws {
        makeViewReady()
        editor.beginMarquee(at: CGPoint(x: 100, y: 100))
        let scale = editor.transform.scale

        assertFailed(call("set_view", ["zoom_percent": 200]), containing: "selection rectangle")
        assertSucceeded(call("get_view"))
        XCTAssertEqual(editor.transform.scale, scale)

        editor.endMarquee()
        assertSucceeded(call("set_view", ["zoom_percent": 200]))
    }

    // MARK: - ファイル

    func testGetDocument() throws {
        let ids = try addTwoLines()
        editor.selectedShapeIds = [UUID(uuidString: ids[0])!]
        let summary = try json(call("get_document"))
        XCTAssertEqual(summary["is_modified"] as? Bool, true)
        XCTAssertEqual(summary["active_layer_index"] as? Int, 0)
        XCTAssertEqual(summary["selected_shape_ids"] as? [String], [ids[0]])
        XCTAssertTrue(summary["file_path"] is NSNull)
        let document = try XCTUnwrap(summary["document"] as? [String: Any])
        let layers = try XCTUnwrap(document["layers"] as? [[String: Any]])
        XCTAssertEqual((layers[0]["shapes"] as? [Any])?.count, 2)
    }

    func testNewAndOpenRefuseToDiscardUnsavedChanges() throws {
        _ = try addTwoLines()
        assertFailed(call("new_document"), containing: "unsaved changes")
        XCTAssertEqual(editor.document.layers[0].shapes.count, 2)

        assertSucceeded(call("new_document", ["discard_changes": true]))
        XCTAssertTrue(editor.document.layers[0].shapes.isEmpty)
        XCTAssertFalse(undo.canUndo)
    }

    func testSaveAndOpenRoundTrip() throws {
        _ = try addTwoLines()
        assertFailed(call("save_document"), containing: "never been saved")

        let url = temporaryURL("lccad")
        defer { try? FileManager.default.removeItem(at: url) }
        assertSucceeded(call("save_document", ["path": .string(url.path)]))
        XCTAssertFalse(fileDocument.isModified)
        let saved = editor.document

        assertSucceeded(call("new_document"))
        assertSucceeded(call("open_document", ["path": .string(url.path)]))
        XCTAssertEqual(editor.document, saved)
        XCTAssertEqual(fileDocument.fileURL, url)

        assertFailed(call("open_document", ["path": "relative.lccad"]), containing: "absolute")
    }

    func testExports() throws {
        _ = try addTwoLines()
        let svg = temporaryURL("svg")
        let dxf = temporaryURL("dxf")
        defer {
            try? FileManager.default.removeItem(at: svg)
            try? FileManager.default.removeItem(at: dxf)
        }
        assertSucceeded(call("export_svg", ["path": .string(svg.path)]))
        assertSucceeded(call("export_dxf", ["path": .string(dxf.path)]))
        XCTAssertEqual(try String(contentsOf: svg, encoding: .utf8), SVGExporter.export(document: editor.document))
        XCTAssertEqual(try String(contentsOf: dxf, encoding: .utf8), DXFExporter.export(document: editor.document))
    }

    // MARK: - 画像

    func testRenderImageReturnsPNG() throws {
        assertFailed(call("render_image"), containing: "no visible shapes")
        assertSucceeded(call("add_shapes", ["shapes": [["type": "rectangle", "x": 0, "y": 0, "width": 100, "height": 50]]]))

        let result = call("render_image", ["width": 400])
        assertSucceeded(result)
        guard case .image(let base64, let mimeType, _, _) = result.content.first else { return XCTFail("no image") }
        XCTAssertEqual(mimeType, "image/png")
        let png = try XCTUnwrap(Data(base64Encoded: base64))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(image.pixelsWide, 400)
        // 100mm を 400 - 余白 48 px に収めるので、高さは 50mm 分 + 余白
        XCTAssertEqual(image.pixelsHigh, Int((50 * (352.0 / 100) + 48).rounded(.up)))
        XCTAssertTrue(text(result).contains("400 x"), text(result))
    }

    /// 画像の範囲には、図形の外にあるステッチ穴と寸法ラベルも含める(review #86)
    func testRenderBoundsIncludeStitchHolesAndDimensionLabels() throws {
        var document = DocumentData()
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0))
        let dimension = DimensionLineShape(start: CGPoint(x: 0, y: 40), end: CGPoint(x: 2, y: 40), offset: 5,
                                           labelOverride: String(repeating: "W", count: 30))
        let iron = PrickingIron(name: "T", holeType: .round, pitch: 4, holeSize: 1.5, holeAngle: 0)
        document.layers[0].shapes = [.line(line), .dimensionLine(dimension)]
        document.prickingIrons = [iron]
        document.layers[0].stitchLines = [StitchLine(
            sourceShapeId: line.id, ironId: iron.id, mode: .fixedPitch,
            holes: [StitchHole(position: CGPoint(x: 5, y: -20), angle: 0)])]

        let bounds = try XCTUnwrap(MCPDocumentImageRenderer.contentBounds(of: document))
        XCTAssertLessThanOrEqual(bounds.minY, -20.75)
        XCTAssertTrue(bounds.contains(dimension.labelBoundingBox))
        XCTAssertGreaterThan(dimension.labelBoundingBox.width, dimension.boundingBox.width, "長いラベルは boundingBox からはみ出す")
    }
}
