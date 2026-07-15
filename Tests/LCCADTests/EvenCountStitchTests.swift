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

    func testClosedCircleEvenCountHasUniformSpacing() {
        // On a circle, equal arc steps give equal chord lengths between neighbours
        // (wrap-around pair included) — verifies the spacing, not just the count.
        let circle = EllipseShape(center: .zero, radiusX: 10, radiusY: 10)
        let walker = PathWalkerFactory.walker(for: .ellipse(circle))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 12)

        XCTAssertEqual(holes.count, 12)
        let chords = (0..<holes.count).map {
            holes[$0].position.distance(to: holes[($0 + 1) % holes.count].position)
        }
        for chord in chords {
            XCTAssertEqual(chord, chords[0], accuracy: 1e-6)
        }
    }

    func testTangentWeldedRunGetsExactCount() {
        // A line welded into a tangent arc forms one smooth open run; Even Count
        // spans the whole welded length (the #24 matched-stitching foundation).
        let line = AnyShape.line(LineShape(start: .zero, end: CGPoint(x: 10, y: 0)))
        let arc = AnyShape.arc(ArcShape(center: CGPoint(x: 10, y: 5), radius: 5,
                                        startAngle: -.pi / 2, endAngle: 0, clockwise: false))
        let paths = StitchPathBuilder.build(from: [line, arc])
        XCTAssertEqual(paths.count, 1, "line + tangent arc must weld into one run")

        let holes = AutoStitchEngine.generateHoles(along: paths[0].walker, iron: iron, mode: .evenCount, holeCount: 9)
        XCTAssertEqual(holes.count, 9)
        XCTAssertEqual(holes.first!.position.distance(to: .zero), 0, accuracy: 1e-6,
                       "first hole sits on the welded run's start")
    }

    func testCorneredPathHonorsEvenCount() {
        // Even Count on a cornered path (駒合わせ): exactly N holes total, with every
        // corner still anchored. Counts below the anchor count are clamped up.
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 12)

        XCTAssertEqual(holes.count, 12)
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)] {
            XCTAssertTrue(holes.contains { $0.position.distance(to: corner) < 1e-6 },
                          "corner \(corner) must keep its anchor hole")
        }

        let clamped = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 3)
        XCTAssertEqual(clamped.count, 4, "count below the 4 corner anchors clamps up")
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
