import XCTest
@testable import LCCAD

final class PrickingIronTests: XCTestCase {

    func testPrickingIronRoundTrip() throws {
        let iron = PrickingIron(name: "Test Diamond", holeType: .diamond, pitch: 4.0, holeSize: 1.5, holeAngle: 0.1)
        let data = try JSONEncoder().encode(iron)
        let decoded = try JSONDecoder().decode(PrickingIron.self, from: data)
        XCTAssertEqual(iron, decoded)
    }

    func testStitchHoleRoundTrip() throws {
        let hole = StitchHole(position: CGPoint(x: 10.5, y: 20.3), angle: 1.2)
        let data = try JSONEncoder().encode(hole)
        let decoded = try JSONDecoder().decode(StitchHole.self, from: data)
        XCTAssertEqual(hole, decoded)
    }

    func testStitchLineRoundTrip() throws {
        let holes = [
            StitchHole(position: CGPoint(x: 0, y: 0), angle: 0),
            StitchHole(position: CGPoint(x: 4, y: 0), angle: 0),
        ]
        let stitchLine = StitchLine(sourceShapeId: UUID(), ironId: UUID(), mode: .fixedPitch, holes: holes)
        let data = try JSONEncoder().encode(stitchLine)
        let decoded = try JSONDecoder().decode(StitchLine.self, from: data)
        XCTAssertEqual(stitchLine, decoded)
    }

    func testDocumentWithPrickingIronsRoundTrip() throws {
        let irons = [
            PrickingIron(name: "Diamond 4mm", holeType: .diamond, pitch: 4.0),
            PrickingIron(name: "Round 3mm", holeType: .round, pitch: 3.0),
        ]
        let doc = DocumentData(prickingIrons: irons)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        let decoded = try JSONDecoder().decode(DocumentData.self, from: data)
        XCTAssertEqual(decoded.prickingIrons.count, 2)
        XCTAssertEqual(decoded.prickingIrons[0].name, "Diamond 4mm")
        XCTAssertEqual(decoded.prickingIrons[1].holeType, .round)
    }

    func testBackwardCompatibility() throws {
        // Simulate a v1.0 file without prickingIrons or stitchLines
        let oldJson = """
        {
          "version": "1.0",
          "settings": { "unit": "mm", "gridSpacing": 10.0, "gridMajorInterval": 5, "snapToGrid": true, "showGrid": true, "showRuler": true },
          "layers": [{ "id": "\(UUID().uuidString)", "name": "Layer 1", "isVisible": true, "isLocked": false, "shapes": [] }]
        }
        """
        let data = oldJson.data(using: .utf8)!
        let doc = try JSONDecoder().decode(DocumentData.self, from: data)
        XCTAssertEqual(doc.prickingIrons.count, 1) // default diamond
        XCTAssertEqual(doc.layers[0].stitchLines.count, 0)
    }
}
