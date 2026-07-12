import XCTest
@testable import LCCAD

/// Even Count mode (#23b): exactly N holes spread evenly over the whole run,
/// ignoring the iron pitch. Covers the engine placement, persistence of the
/// requested count, and the editor pipeline that stores it on the stitch line.
final class EvenCountStitchTests: XCTestCase {

    private let iron = PrickingIron(name: "T", holeType: .diamond, pitch: 4)

    // MARK: - Engine placement

    func testOpenLineGetsExactCountWithEndsAnchored() {
        let line = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        let walker = PathWalkerFactory.walker(for: .line(line))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 5)

        XCTAssertEqual(holes.count, 5)
        XCTAssertEqual(holes.first!.position.x, 0, accuracy: 1e-6)
        XCTAssertEqual(holes.last!.position.x, 100, accuracy: 1e-6)
        for i in 1..<holes.count {
            XCTAssertEqual(holes[i].position.x - holes[i - 1].position.x, 25, accuracy: 1e-6)
        }
    }

    func testClosedCircleGetsExactCountWithNoSeamDuplicate() {
        let circle = EllipseShape(center: .zero, radiusX: 10, radiusY: 10)
        let walker = PathWalkerFactory.walker(for: .ellipse(circle))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 24)

        XCTAssertEqual(holes.count, 24)
        XCTAssertGreaterThan(holes.first!.position.distance(to: holes.last!.position), 1.0,
                             "first and last hole must not coincide at the seam")
    }

    func testCorneredPathIgnoresCount() {
        // Corner-anchored placement wins over the requested count: corners must
        // always carry a hole, so a rectangle keeps its pitch-driven layout.
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        let withCount = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 3)
        let baseline = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .fixedPitch)

        XCTAssertEqual(withCount.count, baseline.count)
        XCTAssertNotEqual(withCount.count, 3)
    }

    func testMissingCountFallsBackToVariablePitch() {
        let line = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        let walker = PathWalkerFactory.walker(for: .line(line))!
        let noCount = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: nil)
        let variable = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .variablePitch)

        XCTAssertEqual(noCount.count, variable.count)
    }

    func testOpenPathClampsCountToBothEnds() {
        let line = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        let walker = PathWalkerFactory.walker(for: .line(line))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 1)

        XCTAssertEqual(holes.count, 2, "an open run always anchors both endpoints")
    }

    // MARK: - Persistence

    func testStitchLineHoleCountRoundTripsThroughCodable() throws {
        let line = StitchLine(sourceShapeIds: [UUID()], ironId: UUID(), mode: .evenCount, holeCount: 24)
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(StitchLine.self, from: data)
        XCTAssertEqual(decoded.holeCount, 24)
        XCTAssertEqual(decoded.mode, .evenCount)
    }

    func testOldStitchLineWithoutHoleCountDecodesAsNil() throws {
        let json = """
        {"id":"\(UUID().uuidString)","sourceShapeIds":["\(UUID().uuidString)"],
         "ironId":"\(UUID().uuidString)","mode":"fixedPitch","holes":[]}
        """
        let decoded = try JSONDecoder().decode(StitchLine.self, from: Data(json.utf8))
        XCTAssertNil(decoded.holeCount)
    }

    // MARK: - Editor pipeline

    @MainActor
    func testAutoStitchStoresCountAndGeneratesExactHoles() {
        var doc = DocumentData.empty()
        let line = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        doc.layers[0].shapes = [.line(line)]
        let editor = EditorViewModel(document: doc)
        editor.selectedShapeIds = [line.id]
        editor.selectedStitchMode = .evenCount
        editor.selectedStitchHoleCount = 7

        editor.autoStitchSelectedShape()

        guard let stitch = editor.document.layers[0].stitchLines.first else {
            return XCTFail("expected a stitch line")
        }
        XCTAssertEqual(stitch.mode, .evenCount)
        XCTAssertEqual(stitch.holeCount, 7)
        XCTAssertEqual(stitch.holes.count, 7)
    }

    @MainActor
    func testPitchModesStoreNilCount() {
        var doc = DocumentData.empty()
        let line = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        doc.layers[0].shapes = [.line(line)]
        let editor = EditorViewModel(document: doc)
        editor.selectedShapeIds = [line.id]
        editor.selectedStitchMode = .fixedPitch
        editor.selectedStitchHoleCount = 7

        editor.autoStitchSelectedShape()

        XCTAssertNil(editor.document.layers[0].stitchLines.first?.holeCount)
    }
}
