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
