import Foundation
import MCP

// MARK: - ツールの定義 (#79)
//
// エージェントが読む説明文は、アプリの UI 文言と同じく英語で書く。
// 引数は snake_case。座標と長さは mm、座標系は左上原点・Y 軸下向き。

enum MCPToolCatalog {
    static let instructions = """
        LCCAD is a leathercraft CAD app. All coordinates and lengths are in millimeters. \
        The coordinate system has its origin at the top-left with the Y axis pointing down. \
        Points are [x, y] arrays. Every tool that changes the document registers one undo step. \
        Call get_document to read the current state and render_image to check the result visually.
        """

    private static let point: Value = [
        "type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2,
        "description": "[x, y] in mm",
    ]

    private static let ids: Value = [
        "type": "array", "items": ["type": "string"], "minItems": 1,
        "description": "Shape ids (UUID strings) from get_document or add_shapes",
    ]

    private static let discardChanges: Value = [
        "type": "boolean",
        "description": "Discard unsaved changes. Without it the call fails when there are unsaved changes",
    ]

    private static let absolutePath: Value = [
        "type": "string", "description": "Absolute file path (~ is expanded)",
    ]

    private static let stroke: Value = [
        "type": "object",
        "description": "Stroke color and line style. The stroke width is fixed at 0.1 mm",
        "properties": [
            "color": ["type": "string", "description": "#RRGGBB or #RRGGBBAA (sRGB). Default #000000"],
            "line_style": ["type": "string", "enum": ["solid", "dashed", "dotted", "dashDot"]],
        ],
    ]

    private static let shapeSpec: Value = [
        "type": "object",
        "description": """
            A shape. Fields by type: \
            line: start, end. \
            rectangle: x, y (top-left), width, height, corner_radius (optional). \
            ellipse: center, radius_x, radius_y. \
            arc: start, end, through (a point the arc passes through; picks the bulge side). \
            bezier: points [{point, control_in, control_out}] (controls default to the anchor), closed. \
            polyline: points [[x, y], ...], closed. \
            text: position, content, font_size, font_name, bold, italic, align (left/center/right). \
            dimension: start, end, offset_point (where the dimension line goes), kind (aligned/horizontal/vertical). \
            Every shape accepts an optional stroke.
            """,
        "properties": [
            "type": ["type": "string", "enum": .array(MCPShapeSpec.Kind.allCases.map { .string($0.rawValue) })],
            "stroke": stroke,
            "start": point, "end": point, "through": point, "center": point,
            "position": point, "offset_point": point,
            "x": ["type": "number"], "y": ["type": "number"],
            "width": ["type": "number"], "height": ["type": "number"],
            "corner_radius": ["type": "number"],
            "radius_x": ["type": "number"], "radius_y": ["type": "number"],
            "points": ["type": "array"],
            "closed": ["type": "boolean"],
            "content": ["type": "string"],
            "font_size": ["type": "number"], "font_name": ["type": "string"],
            "bold": ["type": "boolean"], "italic": ["type": "boolean"],
            "align": ["type": "string", "enum": ["left", "center", "right"]],
            "kind": ["type": "string", "enum": ["aligned", "horizontal", "vertical"]],
        ],
        "required": ["type"],
    ]

    private static func object(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        return .object(schema)
    }

    private static let readOnly = Tool.Annotations(readOnlyHint: true)

    static let tools: [Tool] = [
        Tool(name: "get_document",
             description: "Return the document as JSON (same format as a .lccad file) with the file path, whether it has unsaved changes, the active layer index and the selected shape ids.",
             inputSchema: object([:]), annotations: readOnly),
        Tool(name: "add_shapes",
             description: "Add shapes in one undo step and return their new ids. Shapes go to the active layer unless layer_index is given.",
             inputSchema: object([
                "shapes": ["type": "array", "items": shapeSpec, "minItems": 1],
                "layer_index": ["type": "integer", "description": "Target layer (0-based). Defaults to the active layer"],
             ], required: ["shapes"])),
        Tool(name: "delete_shapes",
             description: "Delete shapes. Stitch lines that belong to them are deleted too.",
             inputSchema: object(["ids": ids], required: ["ids"]),
             annotations: Tool.Annotations(destructiveHint: true)),
        Tool(name: "move_shapes",
             description: "Move shapes by dx, dy (mm). Their stitch holes follow.",
             inputSchema: object([
                "ids": ids, "dx": ["type": "number"], "dy": ["type": "number"],
             ], required: ["ids", "dx", "dy"])),
        Tool(name: "set_stroke",
             description: "Change the stroke color and/or line style of shapes.",
             inputSchema: object([
                "ids": ids,
                "color": ["type": "string", "description": "#RRGGBB or #RRGGBBAA (sRGB)"],
                "line_style": ["type": "string", "enum": ["solid", "dashed", "dotted", "dashDot"]],
             ], required: ["ids"])),
        Tool(name: "set_text",
             description: "Change the properties of a text shape. Omitted fields are left unchanged.",
             inputSchema: object([
                "id": ["type": "string"],
                "content": ["type": "string"],
                "font_size": ["type": "number"], "font_name": ["type": "string"],
                "bold": ["type": "boolean"], "italic": ["type": "boolean"],
                "align": ["type": "string", "enum": ["left", "center", "right"]],
             ], required: ["id"])),
        Tool(name: "select_shapes",
             description: "Select shapes in the editor (replaces the current selection). Pass an empty array to deselect.",
             inputSchema: object([
                "ids": ["type": "array", "items": ["type": "string"]],
             ], required: ["ids"])),
        Tool(name: "undo", description: "Undo the last change.", inputSchema: object([:])),
        Tool(name: "redo", description: "Redo the last undone change.", inputSchema: object([:])),
        Tool(name: "new_document",
             description: "Replace the document with a new empty one. Clears the undo history.",
             inputSchema: object(["discard_changes": discardChanges]),
             annotations: Tool.Annotations(destructiveHint: true)),
        Tool(name: "open_document",
             description: "Open a .lccad file. Clears the undo history.",
             inputSchema: object(["path": absolutePath, "discard_changes": discardChanges], required: ["path"]),
             annotations: Tool.Annotations(destructiveHint: true)),
        Tool(name: "save_document",
             description: "Save the document as a .lccad file. Without path, saves to the current file.",
             inputSchema: object(["path": absolutePath])),
        Tool(name: "export_svg",
             description: "Export the visible layers as SVG (real size in mm).",
             inputSchema: object(["path": absolutePath], required: ["path"])),
        Tool(name: "export_dxf",
             description: "Export the visible layers as DXF (real size in mm).",
             inputSchema: object(["path": absolutePath], required: ["path"])),
        Tool(name: "render_image",
             description: "Render the visible shapes and stitch holes as a PNG on a white background, fitted to their bounds.",
             inputSchema: object([
                "width": ["type": "integer", "minimum": 200, "maximum": 4096,
                          "description": "Image width in pixels. Default 1600"],
             ]), annotations: readOnly),
    ]
}

extension Tool.Content {
    /// 注釈なしのテキスト
    static func plainText(_ text: String) -> Self {
        .text(text: text, annotations: nil, _meta: nil)
    }
}

// MARK: - ツールの実行

/// ツールの呼び出しを、`EditorViewModel` の操作メソッドにつなぐ (#79)。
/// 選択中の図形に対して働く操作は、一時的に選択を差し替えて呼び、元の選択に戻す
@MainActor
struct MCPToolExecutor {
    let editor: EditorViewModel

    struct ToolError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    func call(_ name: String, arguments: [String: Value]?) -> CallTool.Result {
        do {
            return try run(name, arguments: arguments ?? [:])
        } catch let error as DecodingError {
            return Self.failure("Invalid arguments: \(Self.describe(error))")
        } catch {
            return Self.failure("\(error)")
        }
    }

    private func run(_ name: String, arguments: [String: Value]) throws -> CallTool.Result {
        switch name {
        case "get_document": return try getDocument()
        case "add_shapes": return try addShapes(decode(AddShapesArguments.self, arguments))
        case "delete_shapes": return try deleteShapes(decode(IdsArguments.self, arguments))
        case "move_shapes": return try moveShapes(decode(MoveArguments.self, arguments))
        case "set_stroke": return try setStroke(decode(StrokeArguments.self, arguments))
        case "set_text": return try setText(decode(TextArguments.self, arguments))
        case "select_shapes": return try selectShapes(decode(SelectArguments.self, arguments))
        case "undo": return try undo()
        case "redo": return try redo()
        case "new_document": return try newDocument(decode(DiscardArguments.self, arguments))
        case "open_document": return try openDocument(decode(PathDiscardArguments.self, arguments))
        case "save_document": return try saveDocument(decode(OptionalPathArguments.self, arguments))
        case "export_svg":
            let url = try Self.fileURL(decode(PathArguments.self, arguments).path)
            try editor.exportSVG(to: url)
            return Self.success(["path": .string(url.path)])
        case "export_dxf":
            let url = try Self.fileURL(decode(PathArguments.self, arguments).path)
            try editor.exportDXF(to: url)
            return Self.success(["path": .string(url.path)])
        case "render_image": return try renderImage(decode(RenderArguments.self, arguments))
        default:
            throw ToolError("Unknown tool: \(name)")
        }
    }

    // MARK: Arguments

    private struct AddShapesArguments: Decodable { let shapes: [MCPShapeSpec]; let layerIndex: Int? }
    private struct IdsArguments: Decodable { let ids: [String] }
    private struct MoveArguments: Decodable { let ids: [String]; let dx: Double; let dy: Double }
    private struct StrokeArguments: Decodable { let ids: [String]; let color: String?; let lineStyle: LineStyle? }
    private struct TextArguments: Decodable {
        let id: String
        let content: String?
        let fontSize: Double?
        let fontName: String?
        let bold: Bool?
        let italic: Bool?
        let align: TextAlignment?
    }
    private struct SelectArguments: Decodable { let ids: [String] }
    private struct DiscardArguments: Decodable { let discardChanges: Bool? }
    private struct PathArguments: Decodable { let path: String }
    private struct OptionalPathArguments: Decodable { let path: String? }
    private struct PathDiscardArguments: Decodable { let path: String; let discardChanges: Bool? }
    private struct RenderArguments: Decodable { let width: Int? }

    private func decode<T: Decodable>(_ type: T.Type, _ arguments: [String: Value]) throws -> T {
        let data = try JSONEncoder().encode(Value.object(arguments))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    // MARK: Document

    private func getDocument() throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let documentJSON = try JSONSerialization.jsonObject(with: encoder.encode(editor.document))
        let summary: [String: Any] = [
            "file_path": editor.fileDocument?.fileURL?.path ?? NSNull(),
            "is_modified": editor.fileDocument?.isModified ?? false,
            "active_layer_index": editor.safeActiveLayerIndex,
            "selected_shape_ids": editor.selectedShapeIds.map(\.uuidString).sorted(),
            "document": documentJSON,
        ]
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
        return CallTool.Result(content: [.plainText(String(decoding: data, as: UTF8.self))])
    }

    private func newDocument(_ arguments: DiscardArguments) throws -> CallTool.Result {
        try requireNoUnsavedChanges(unless: arguments.discardChanges)
        try editor.newDocument()
        return Self.success([:])
    }

    private func openDocument(_ arguments: PathDiscardArguments) throws -> CallTool.Result {
        let url = try Self.fileURL(arguments.path)
        try requireNoUnsavedChanges(unless: arguments.discardChanges)
        try editor.openDocument(at: url)
        return Self.success(["path": .string(url.path)])
    }

    private func saveDocument(_ arguments: OptionalPathArguments) throws -> CallTool.Result {
        guard let fileDocument = editor.fileDocument else { throw EditorOperationError.noFileDocument }
        let url: URL
        if let path = arguments.path {
            url = try Self.fileURL(path)
        } else if let current = fileDocument.fileURL {
            url = current
        } else {
            throw ToolError("The document has never been saved. Pass a path")
        }
        try fileDocument.write(to: url)
        return Self.success(["path": .string(url.path)])
    }

    private func requireNoUnsavedChanges(unless discard: Bool?) throws {
        guard discard != true, editor.fileDocument?.isModified == true else { return }
        throw ToolError("The document has unsaved changes. Save it first, or pass discard_changes: true")
    }

    // MARK: Shapes

    private func addShapes(_ arguments: AddShapesArguments) throws -> CallTool.Result {
        let shapes = arguments.shapes.map(\.shape)
        guard !shapes.isEmpty else { throw ToolError("shapes must not be empty") }
        let previousLayer = editor.activeLayerIndex
        if let layerIndex = arguments.layerIndex {
            guard editor.document.layers.indices.contains(layerIndex) else {
                throw ToolError("layer_index \(layerIndex) is out of range (0..<\(editor.document.layers.count))")
            }
            editor.activeLayerIndex = layerIndex
        }
        editor.addShapes(shapes, actionName: "Add Shapes")
        if arguments.layerIndex != nil {
            editor.activeLayerIndex = previousLayer
        }
        return Self.success(["ids": .array(shapes.map { .string($0.id.uuidString) })])
    }

    private func deleteShapes(_ arguments: IdsArguments) throws -> CallTool.Result {
        let ids = try shapeIds(arguments.ids)
        withSelection(ids) { editor.deleteSelectedShapes() }
        return Self.success(["deleted": .int(ids.count)])
    }

    private func moveShapes(_ arguments: MoveArguments) throws -> CallTool.Result {
        let ids = try shapeIds(arguments.ids)
        guard arguments.dx.isFinite, arguments.dy.isFinite else { throw ToolError("dx and dy must be finite numbers") }
        let old = editor.document
        withSelection(ids) {
            editor.moveSelectedShapes(by: CGPoint(x: arguments.dx, y: arguments.dy))
            editor.commitMoveWithUndo(oldDocument: old)
        }
        return Self.success([:])
    }

    private func setStroke(_ arguments: StrokeArguments) throws -> CallTool.Result {
        let ids = try shapeIds(arguments.ids)
        guard arguments.color != nil || arguments.lineStyle != nil else {
            throw ToolError("Pass color and/or line_style")
        }
        let color = try arguments.color.map(MCPColor.parse)
        withSelection(ids) {
            editor.updateStroke { stroke in
                if let color { stroke.color = color }
                if let lineStyle = arguments.lineStyle {
                    stroke.lineStyle = lineStyle
                    stroke.dashPattern = lineStyle.dashPattern
                }
            }
        }
        return Self.success([:])
    }

    private func setText(_ arguments: TextArguments) throws -> CallTool.Result {
        let id = try shapeIds([arguments.id])[0]
        guard case .text = editor.findShape(id: id) else { throw ToolError("Shape \(arguments.id) is not a text shape") }
        if let fontSize = arguments.fontSize, !(fontSize > 0 && fontSize.isFinite) {
            throw ToolError("font_size must be positive")
        }
        withSelection([id]) {
            editor.updateTextProperty { text in
                if let content = arguments.content { text.content = content }
                if let fontSize = arguments.fontSize { text.fontSize = fontSize }
                if let fontName = arguments.fontName { text.fontName = fontName }
                if let bold = arguments.bold { text.isBold = bold }
                if let italic = arguments.italic { text.isItalic = italic }
                if let align = arguments.align { text.textAlignment = align }
            }
        }
        return Self.success([:])
    }

    private func selectShapes(_ arguments: SelectArguments) throws -> CallTool.Result {
        let ids = arguments.ids.isEmpty ? [] : try shapeIds(arguments.ids)
        editor.selectedShapeIds = Set(ids)
        return Self.success(["selected": .int(ids.count)])
    }

    /// 文字列の id を UUID にし、トップレベルの図形として存在するかを確かめる
    private func shapeIds(_ strings: [String]) throws -> [UUID] {
        guard !strings.isEmpty else { throw ToolError("ids must not be empty") }
        var ids: [UUID] = []
        var unknown: [String] = []
        for string in strings {
            if let id = UUID(uuidString: string), editor.findShape(id: id) != nil {
                ids.append(id)
            } else {
                unknown.append(string)
            }
        }
        guard unknown.isEmpty else { throw ToolError("Unknown shape ids: \(unknown.joined(separator: ", "))") }
        return ids
    }

    /// 選択を `ids` に差し替えて `body` を呼び、終わったら元の選択(消えた図形を除く)に戻す
    private func withSelection(_ ids: [UUID], _ body: () -> Void) {
        let previous = editor.selectedShapeIds
        editor.selectedShapeIds = Set(ids)
        body()
        editor.selectedShapeIds = previous.filter { editor.findShape(id: $0) != nil }
    }

    // MARK: Undo

    private func undo() throws -> CallTool.Result {
        guard let undoManager = editor.undoManager else { throw ToolError("Undo is not available") }
        guard undoManager.canUndo else { throw ToolError("Nothing to undo") }
        let actionName = undoManager.undoActionName
        undoManager.undo()
        return Self.success(undoState(undoManager, ["undone": .string(actionName)]))
    }

    private func redo() throws -> CallTool.Result {
        guard let undoManager = editor.undoManager else { throw ToolError("Redo is not available") }
        guard undoManager.canRedo else { throw ToolError("Nothing to redo") }
        let actionName = undoManager.redoActionName
        undoManager.redo()
        return Self.success(undoState(undoManager, ["redone": .string(actionName)]))
    }

    private func undoState(_ undoManager: UndoManager, _ fields: [String: Value]) -> [String: Value] {
        fields.merging(["can_undo": .bool(undoManager.canUndo), "can_redo": .bool(undoManager.canRedo)]) { a, _ in a }
    }

    // MARK: Image

    private func renderImage(_ arguments: RenderArguments) throws -> CallTool.Result {
        let rendered = try MCPDocumentImageRenderer.renderPNG(
            document: editor.document,
            width: arguments.width ?? MCPDocumentImageRenderer.defaultWidth)
        let info = String(
            format: "%d x %d px, %.4g px/mm, bounds x %.4g..%.4g mm, y %.4g..%.4g mm",
            rendered.pixelWidth, rendered.pixelHeight, rendered.pixelsPerMillimeter,
            rendered.bounds.minX, rendered.bounds.maxX, rendered.bounds.minY, rendered.bounds.maxY)
        return CallTool.Result(content: [
            .image(data: rendered.png.base64EncodedString(), mimeType: "image/png", annotations: nil, _meta: nil),
            .plainText(info),
        ])
    }

    // MARK: Helpers

    /// 絶対パスだけを受け付ける(~ は展開する)
    static func fileURL(_ path: String) throws -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw ToolError("path must be absolute: \(path)") }
        return URL(fileURLWithPath: expanded)
    }

    private static func success(_ fields: [String: Value]) -> CallTool.Result {
        var object = fields
        object["ok"] = .bool(true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = (try? encoder.encode(Value.object(object))).map { String(decoding: $0, as: UTF8.self) } ?? "{\"ok\":true}"
        return CallTool.Result(content: [.plainText(text)])
    }

    private static func failure(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.plainText(message)], isError: true)
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
            return keys.isEmpty ? "" : " at \(keys.joined(separator: "."))"
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing \"\(key.stringValue)\"\(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(context.debugDescription)\(path(context))"
        @unknown default:
            return "\(error)"
        }
    }
}
