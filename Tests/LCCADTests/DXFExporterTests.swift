import XCTest
import CoreGraphics
@testable import LCCAD

final class DXFExporterTests: XCTestCase {

    // MARK: - Layer name sanitization

    func testLayerNameWithNewlineDoesNotInjectEntity() {
        var doc = DocumentData()
        doc.layers = [Layer(name: "Evil\n0\nLINE\nInjected")]
        doc.layers[0].shapes.append(.line(LineShape(start: .zero, end: CGPoint(x: 10, y: 10))))

        let dxf = DXFExporter.export(document: doc)

        // The sanitized layer name must appear without raw newlines
        XCTAssertTrue(dxf.contains("Evil_0_LINE_Injected"),
                      "Control characters in layer names must be replaced with underscores")

        // There should be exactly one LINE entity (ours), not an injected one
        let lineCount = dxf.components(separatedBy: "\n0\nLINE\n").count - 1
        XCTAssertEqual(lineCount, 1, "Injected LINE entity detected in output")
    }

    func testLayerNameWithSpaces() {
        var doc = DocumentData()
        doc.layers = [Layer(name: "My Layer")]
        let dxf = DXFExporter.export(document: doc)
        XCTAssertTrue(dxf.contains("My_Layer"))
    }

    func testLayerNameWithBraces() {
        var doc = DocumentData()
        doc.layers = [Layer(name: "{evil}")]
        let dxf = DXFExporter.export(document: doc)
        XCTAssertTrue(dxf.contains("_evil_"))
    }

    // MARK: - Text content sanitization

    func testTextContentWithNewlineDoesNotInjectEntity() {
        var doc = DocumentData()
        doc.layers = [Layer(name: "L1")]
        let evilText = TextShape(position: CGPoint(x: 0, y: 0), content: "hello\n0\nLINE\n10\n99.0\n20\n99.0")
        doc.layers[0].shapes.append(.text(evilText))

        let dxf = DXFExporter.export(document: doc)

        // No LINE entity should appear — only the TEXT we requested
        let lineCount = dxf.components(separatedBy: "\n0\nLINE\n").count - 1
        XCTAssertEqual(lineCount, 0, "Text content leaked control characters and injected a LINE entity")

        // One TEXT entity should be present
        let textCount = dxf.components(separatedBy: "\n0\nTEXT\n").count - 1
        XCTAssertEqual(textCount, 1)
    }

    func testTextContentWithCarriageReturn() {
        var doc = DocumentData()
        doc.layers = [Layer(name: "L1")]
        doc.layers[0].shapes.append(.text(TextShape(position: .zero, content: "a\rb")))

        let dxf = DXFExporter.export(document: doc)
        XCTAssertFalse(dxf.contains("a\rb"))
    }

    // MARK: - Happy path (unchanged output for normal input)

    func testNormalContentUnchanged() {
        var doc = DocumentData()
        doc.layers = [Layer(name: "Pattern")]
        doc.layers[0].shapes.append(.line(LineShape(start: .zero, end: CGPoint(x: 50, y: 0))))

        let dxf = DXFExporter.export(document: doc)
        XCTAssertTrue(dxf.contains("Pattern"))
        XCTAssertTrue(dxf.contains("\n0\nLINE\n"))
    }
}
