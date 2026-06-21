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

    func testExportEllipseToSVG() {
        let ellipse = EllipseShape(center: CGPoint(x: 30, y: 40), radiusX: 20, radiusY: 10)
        let layer = Layer(name: "Test", shapes: [.ellipse(ellipse)])
        let doc = DocumentData(layers: [layer])
        let svg = SVGExporter.export(document: doc)

        XCTAssertTrue(svg.contains("<ellipse"))
        XCTAssertTrue(svg.contains("cx=\"30.00\""))
        XCTAssertTrue(svg.contains("cy=\"40.00\""))
        XCTAssertTrue(svg.contains("rx=\"20.00\""))
        XCTAssertTrue(svg.contains("ry=\"10.00\""))
        // No rotation → no transform attribute should be emitted.
        XCTAssertFalse(svg.contains("transform="), "Unrotated ellipse must not emit a transform")
    }

    func testRotatedEllipseEmitsTransform() {
        var ellipse = EllipseShape(center: CGPoint(x: 10, y: 10), radiusX: 5, radiusY: 3)
        ellipse.rotation = .pi / 4
        let layer = Layer(name: "Test", shapes: [.ellipse(ellipse)])
        let doc = DocumentData(layers: [layer])
        let svg = SVGExporter.export(document: doc)

        // π/4 rad = 45° rotation around the ellipse center (10, 10).
        XCTAssertTrue(svg.contains("transform=\"rotate(45.00 10.00 10.00)\""),
                      "Rotated ellipse should emit a rotate transform about its center")
    }

    func testRotatedEllipseViewBoxEncompassesRotation() {
        // A 100x10 ellipse rotated 90° becomes 10x100. The viewBox (bbox + 5mm
        // margin each side) must be 20 x 110, not 110 x 20 — i.e. the rotated
        // ellipse must not be clipped.
        var ellipse = EllipseShape(center: CGPoint(x: 0, y: 0), radiusX: 50, radiusY: 5)
        ellipse.rotation = .pi / 2
        let layer = Layer(name: "Test", shapes: [.ellipse(ellipse)])
        let doc = DocumentData(layers: [layer])
        let svg = SVGExporter.export(document: doc)

        XCTAssertTrue(svg.contains("width=\"20.00mm\" height=\"110.00mm\""),
                      "viewBox must grow to the rotated ellipse's extents, not the unrotated AABB")
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
