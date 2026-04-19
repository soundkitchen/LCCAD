import XCTest
@testable import LCCAD

final class DocumentSerializationTests: XCTestCase {

    func testDocumentRoundTrip() throws {
        var doc = DocumentData.empty()

        // Add a line to the first layer
        let line = LineShape(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 100, y: 50))
        doc.layers[0].shapes.append(.line(line))

        // Add a rectangle
        let rect = RectangleShape(origin: CGPoint(x: 30, y: 40), size: CGSize(width: 80, height: 60))
        doc.layers[0].shapes.append(.rectangle(rect))

        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(doc)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DocumentData.self, from: data)

        // Verify
        XCTAssertEqual(decoded.version, "1.0")
        XCTAssertEqual(decoded.layers.count, 1)
        XCTAssertEqual(decoded.layers[0].shapes.count, 2)
        XCTAssertEqual(decoded.layers[0].name, "Layer 1")
        XCTAssertEqual(decoded.settings.unit, .millimeters)
    }

    func testAllShapeTypesRoundTrip() throws {
        var doc = DocumentData.empty()

        doc.layers[0].shapes.append(.line(LineShape(start: .zero, end: CGPoint(x: 10, y: 10))))
        doc.layers[0].shapes.append(.rectangle(RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))))
        doc.layers[0].shapes.append(.ellipse(EllipseShape(center: CGPoint(x: 5, y: 5), radiusX: 10, radiusY: 8)))
        doc.layers[0].shapes.append(.arc(ArcShape(center: CGPoint(x: 5, y: 5), radius: 10, startAngle: 0, endAngle: .pi)))
        doc.layers[0].shapes.append(.dot(DotShape(position: CGPoint(x: 5, y: 5))))
        doc.layers[0].shapes.append(.bezier(BezierShape(points: [
            BezierPoint(point: .zero, controlIn: .zero, controlOut: CGPoint(x: 5, y: 0)),
            BezierPoint(point: CGPoint(x: 10, y: 10), controlIn: CGPoint(x: 5, y: 10), controlOut: CGPoint(x: 10, y: 10))
        ])))

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(DocumentData.self, from: data)

        XCTAssertEqual(decoded.layers[0].shapes.count, 6)
    }

    func testHitTestLine() {
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0))
        XCTAssertTrue(line.hitTest(point: CGPoint(x: 50, y: 0), tolerance: 3))
        XCTAssertTrue(line.hitTest(point: CGPoint(x: 50, y: 2), tolerance: 3))
        XCTAssertFalse(line.hitTest(point: CGPoint(x: 50, y: 10), tolerance: 3))
    }

    func testHitTestRectangle() {
        let rect = RectangleShape(origin: CGPoint(x: 10, y: 10), size: CGSize(width: 100, height: 50))
        // On the edge
        XCTAssertTrue(rect.hitTest(point: CGPoint(x: 10, y: 35), tolerance: 3))
        // In the center (should not hit, only edges)
        XCTAssertFalse(rect.hitTest(point: CGPoint(x: 60, y: 35), tolerance: 3))
        // Far away
        XCTAssertFalse(rect.hitTest(point: CGPoint(x: 200, y: 200), tolerance: 3))
    }

    func testPointDistance() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 3, y: 4)
        XCTAssertEqual(a.distance(to: b), 5.0, accuracy: 0.001)
    }

    func testLengthUnitConversion() {
        XCTAssertEqual(LengthUnit.inches.toMillimeters(1), 25.4, accuracy: 0.001)
        XCTAssertEqual(LengthUnit.millimeters.fromMillimeters(25.4), 25.4, accuracy: 0.001)
        XCTAssertEqual(LengthUnit.inches.fromMillimeters(25.4), 1.0, accuracy: 0.001)
    }
}
