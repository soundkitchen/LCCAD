import XCTest
@testable import LCCAD

/// Dirty-tracking state machine behind the unsaved-changes guard (Issue #22).
@MainActor
final class DocumentDirtyTrackingTests: XCTestCase {

    func testNewDocumentIsNotModified() {
        let doc = LCCADFileDocument()
        XCTAssertFalse(doc.isModified)
    }

    func testEditingMarksModified() {
        let doc = LCCADFileDocument()
        doc.data.layers[0].name = "Renamed"
        XCTAssertTrue(doc.isModified)
    }

    func testMarkSavedClearsModified() {
        let doc = LCCADFileDocument()
        doc.data.settings.gridSpacing = 2.0
        XCTAssertTrue(doc.isModified)

        doc.markSaved()
        XCTAssertFalse(doc.isModified)
    }

    /// `isModified` is value-equality based, so reverting an edit clears it.
    func testRevertingEditClearsModified() {
        let doc = LCCADFileDocument()
        let original = doc.data.settings.gridSpacing

        doc.data.settings.gridSpacing = original + 1
        XCTAssertTrue(doc.isModified)

        doc.data.settings.gridSpacing = original
        XCTAssertFalse(doc.isModified)
    }

    func testWriteToURLClearsModifiedAndSetsFileURL() throws {
        let doc = LCCADFileDocument()
        doc.data.layers[0].name = "Saved layer"
        XCTAssertTrue(doc.isModified)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("lccad")
        defer { try? FileManager.default.removeItem(at: url) }

        try doc.write(to: url)

        XCTAssertFalse(doc.isModified)
        XCTAssertEqual(doc.fileURL, url)

        // The persisted file round-trips back to the same document data.
        let decoded = try JSONDecoder().decode(DocumentData.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded, doc.data)
    }

    /// パネルなしの読み込み (#78): 書き出したファイルを読み戻すと、同じ内容で未変更になる
    func testReadFromURLReplacesDocument() throws {
        let source = LCCADFileDocument()
        source.data.layers[0].name = "From file"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("lccad")
        defer { try? FileManager.default.removeItem(at: url) }
        try source.write(to: url)

        let doc = LCCADFileDocument()
        doc.data.settings.gridSpacing = 7
        let before = doc.loadGeneration

        try doc.read(from: url)

        XCTAssertEqual(doc.data, source.data)
        XCTAssertEqual(doc.fileURL, url)
        XCTAssertFalse(doc.isModified)
        XCTAssertEqual(doc.loadGeneration, before + 1)
    }

    func testReadFromInvalidURLThrowsAndKeepsDocument() {
        let doc = LCCADFileDocument()
        doc.data.layers[0].name = "Unsaved"
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("lccad")

        XCTAssertThrowsError(try doc.read(from: missing))
        XCTAssertEqual(doc.data.layers[0].name, "Unsaved")
        XCTAssertNil(doc.fileURL)
    }

    /// レイヤーが空のファイルは、読み込み時に「Layer 1」を 1 枚持たせる (#78)
    func testDecodingEmptyLayersAddsDefaultLayer() throws {
        var data = DocumentData()
        data.layers = []
        let json = try JSONEncoder().encode(data)

        let decoded = try JSONDecoder().decode(DocumentData.self, from: json)
        XCTAssertEqual(decoded.layers.map(\.name), ["Layer 1"])
    }

    func testResetToNewDocumentClearsEverything() {
        let doc = LCCADFileDocument(fileURL: URL(fileURLWithPath: "/tmp/x.lccad"))
        doc.data.layers[0].name = "Edited"
        let before = doc.loadGeneration

        doc.resetToNewDocument()

        // レイヤーの id は作るたびに変わるので、名前と中身で比べる
        XCTAssertEqual(doc.data.layers.map(\.name), DocumentData.empty().layers.map(\.name))
        XCTAssertTrue(doc.data.layers.allSatisfy { $0.shapes.isEmpty })
        XCTAssertNil(doc.fileURL)
        XCTAssertFalse(doc.isModified)
        XCTAssertEqual(doc.loadGeneration, before + 1)
    }

    func testNotifyDocumentReplacedBumpsLoadGeneration() {
        let doc = LCCADFileDocument()
        let before = doc.loadGeneration
        doc.notifyDocumentReplaced()
        XCTAssertEqual(doc.loadGeneration, before + 1)
    }

    /// A stale active-layer index from a larger document must not index out of
    /// bounds after the document shrinks (e.g. New / Open of a smaller file).
    func testActiveLayerIsSafeAfterDocumentShrinks() {
        let editor = EditorViewModel(document: DocumentData(layers: [
            Layer(name: "L1"), Layer(name: "L2"), Layer(name: "L3"),
        ]))
        editor.activeLayerIndex = 2

        // Simulate a New load (single layer) without resetting the index.
        editor.document = .empty()

        // Must not crash, and must resolve to a valid layer.
        XCTAssertEqual(editor.document.layers.count, 1)
        XCTAssertEqual(editor.activeLayer.name, editor.document.layers[0].name)
    }

    func testEditingAfterSaveMarksModifiedAgain() throws {
        let doc = LCCADFileDocument()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("lccad")
        defer { try? FileManager.default.removeItem(at: url) }

        try doc.write(to: url)
        XCTAssertFalse(doc.isModified)

        doc.data.layers.append(Layer(name: "Layer 2"))
        XCTAssertTrue(doc.isModified)
    }
}
