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

    // MARK: - Ellipse polyline approximation (regression: was silently dropped)

    func testEllipseEmitsLineSegments() {
        var doc = DocumentData()
        doc.layers = [Layer(name: "L1")]
        doc.layers[0].shapes.append(.ellipse(
            EllipseShape(center: CGPoint(x: 10, y: 10), radiusX: 5, radiusY: 3)))

        let dxf = DXFExporter.export(document: doc)

        // The ellipse must be approximated by a closed 72-segment polyline,
        // not silently omitted (the original bug returned "").
        let lineCount = dxf.components(separatedBy: "\n0\nLINE\n").count - 1
        XCTAssertEqual(lineCount, 72, "Ellipse should emit 72 LINE segments, not be dropped")
    }

    func testRotatedEllipseStillEmitsSegments() {
        var doc = DocumentData()
        doc.layers = [Layer(name: "L1")]
        var ellipse = EllipseShape(center: CGPoint(x: 10, y: 10), radiusX: 5, radiusY: 3)
        ellipse.rotation = .pi / 4
        doc.layers[0].shapes.append(.ellipse(ellipse))

        let dxf = DXFExporter.export(document: doc)
        let lineCount = dxf.components(separatedBy: "\n0\nLINE\n").count - 1
        XCTAssertEqual(lineCount, 72, "Rotated ellipse must also emit its polyline approximation")

        // The rotation must actually be applied to the emitted coordinates, not
        // just produce the right number of segments. The θ=0 vertex sits at
        // (center.x + radiusX, center.y) = (15, 10) when unrotated; a π/4
        // rotation around the center (10, 10) moves it to (13.5355, 13.5355).
        XCTAssertFalse(dxf.contains("\n10\n15.0000\n20\n10.0000\n"),
                       "Unrotated θ=0 vertex must not appear once the ellipse is rotated")
        XCTAssertTrue(dxf.contains("\n10\n13.5355\n20\n13.5355\n"),
                      "Rotated θ=0 vertex (13.5355, 13.5355) should appear in the output")
    }

    // MARK: - Dimension line

    func testDimensionEmitsLinesAndText() {
        var doc = DocumentData()
        doc.layers = [Layer(name: "L1")]
        doc.layers[0].shapes.append(.dimensionLine(
            DimensionLineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 20, y: 0),
                               offset: 5, kind: .horizontal)))

        let dxf = DXFExporter.export(document: doc)

        // 3 base lines (2 extension + 1 dimension) + 2 lines per arrowhead (×2) = 7
        let lineCount = dxf.components(separatedBy: "\n0\nLINE\n").count - 1
        XCTAssertEqual(lineCount, 7, "Dimension should emit its extension/dimension/arrow lines")
        // And a single TEXT entity for the label.
        let textCount = dxf.components(separatedBy: "\n0\nTEXT\n").count - 1
        XCTAssertEqual(textCount, 1)
    }

    func testDimensionLabelIsMillimetersEvenForInchDocument() {
        var doc = DocumentData()
        doc.settings.unit = .inches
        doc.layers = [Layer(name: "L1")]
        // 25.4mm horizontal span = 1.0 inch
        doc.layers[0].shapes.append(.dimensionLine(
            DimensionLineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 25.4, y: 0),
                               offset: 5, kind: .horizontal)))

        let dxf = DXFExporter.export(document: doc)

        // Exported coordinates are mm, so the label must be the mm value, not inches.
        XCTAssertTrue(dxf.contains("\n1\n25.4\n"), "Dimension label should be the mm value (25.4)")
        XCTAssertFalse(dxf.contains("\n1\n1.0\n"), "Inch-converted label (1.0) must not be exported")
    }
}
