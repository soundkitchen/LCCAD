import XCTest
@testable import LCCAD

final class SVGExporterTests: XCTestCase {

    func testExportLineToSVG() {
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 50))
        let layer = Layer(name: "Test", shapes: [.line(line)])
        let doc = DocumentData(layers: [layer])
        let svg = SVGExporter.export(document: doc)

        XCTAssertTrue(svg.contains("<line"))
        XCTAssertTrue(svg.contains("x1=\"0.00\""))
        XCTAssertTrue(svg.contains("y2=\"50.00\""))
    }

    func testExportRectangleToSVG() {
        let rect = RectangleShape(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 80, height: 60))
        let layer = Layer(name: "Test", shapes: [.rectangle(rect)])
        let doc = DocumentData(layers: [layer])
        let svg = SVGExporter.export(document: doc)

        XCTAssertTrue(svg.contains("<rect"))
        XCTAssertTrue(svg.contains("width=\"80.00\""))
    }

    func testSVGHeaderContainsViewBox() {
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 50, y: 50))
        let layer = Layer(name: "Test", shapes: [.line(line)])
        let doc = DocumentData(layers: [layer])
        let svg = SVGExporter.export(document: doc)

        XCTAssertTrue(svg.contains("viewBox="))
        XCTAssertTrue(svg.contains("xmlns"))
        XCTAssertTrue(svg.contains("</svg>"))
    }

    func testExportStitchHolesToSVG() {
        let iron = PrickingIron.defaultDiamond
        let holes = [
            StitchHole(position: CGPoint(x: 10, y: 0), angle: 0),
            StitchHole(position: CGPoint(x: 20, y: 0), angle: 0),
        ]
        let stitchLine = StitchLine(sourceShapeId: UUID(), ironId: iron.id, holes: holes)
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        let layer = Layer(name: "Test", shapes: [.line(line)], stitchLines: [stitchLine])
        let doc = DocumentData(prickingIrons: [iron], layers: [layer])
        let svg = SVGExporter.export(document: doc)

        XCTAssertTrue(svg.contains("class=\"stitch\""))
        XCTAssertTrue(svg.contains("<circle"))
    }

    func testDimensionExportsArrowsAndMmLabel() {
        var doc = DocumentData()
        doc.settings.unit = .inches
        doc.layers = [Layer(name: "L1")]
        doc.layers[0].shapes.append(.dimensionLine(
            DimensionLineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 25.4, y: 0),
                               offset: 5, kind: .horizontal)))

        let svg = SVGExporter.export(document: doc)

        XCTAssertTrue(svg.contains("<polygon"), "Arrowheads should be emitted as polygons")
        // Label uses mm (matches the file's mm coordinates), not the inch display unit.
        XCTAssertTrue(svg.contains(">25.4</text>"), "Dimension label should be the mm value")
        XCTAssertFalse(svg.contains(">1.0</text>"), "Inch-converted label must not appear")
    }
}
