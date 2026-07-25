import XCTest
@testable import LCCAD

/// Hybrid mode (#23c): exact pitch from the run start up to a user-picked point,
/// then the leftover stretch is evened so the last hole lands on the run end.
/// Covers the engine placement, persistence of the split point, and the editor
/// pick flow (Auto Stitch → click on the path → commit).
final class HybridStitchTests: XCTestCase {

    private let iron = PrickingIron(name: "T", holeType: .diamond, pitch: 4)

    // MARK: - Engine placement

    func testFixedRegionKeepsExactPitchAndTailIsEvened() {
        // 29mm line, split at 10mm: fixed holes at 0/4/8, then the 21mm tail is
        // evened into 5 steps of 4.2mm ending exactly on the endpoint.
        let line = LineShape(start: .zero, end: CGPoint(x: 29, y: 0))
        let walker = PathWalkerFactory.walker(for: .line(line))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .hybrid, fixedLength: 10)

        XCTAssertEqual(holes.count, 8)
        for (i, x) in [0.0, 4.0, 8.0].enumerated() {
            XCTAssertEqual(holes[i].position.x, x, accuracy: 1e-6, "fixed region marches at the exact pitch")
        }
        for i in 4..<8 {
            XCTAssertEqual(holes[i].position.x - holes[i - 1].position.x, 4.2, accuracy: 1e-6,
                           "tail spacing is evened")
        }
        XCTAssertEqual(holes.last!.position.x, 29, accuracy: 1e-6, "last hole lands on the run end")
    }

    func testZeroFixedLengthMatchesVariablePitch() {
        let line = LineShape(start: .zero, end: CGPoint(x: 29, y: 0))
        let walker = PathWalkerFactory.walker(for: .line(line))!
        let hybrid = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .hybrid, fixedLength: 0)
        let variable = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .variablePitch)

        XCTAssertEqual(hybrid.count, variable.count)
        for (h, v) in zip(hybrid, variable) {
            XCTAssertEqual(h.position.distance(to: v.position), 0, accuracy: 1e-6)
        }
    }

    func testFixedLengthBeyondEndKeepsPitchAndAbsorbsRemainder() {
        // Split past the end: the exact pitch runs as far as it fits (0…28) and the
        // 1mm remainder becomes a single final step onto the endpoint.
        let line = LineShape(start: .zero, end: CGPoint(x: 29, y: 0))
        let walker = PathWalkerFactory.walker(for: .line(line))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .hybrid, fixedLength: 100)

        XCTAssertEqual(holes.count, 9)
        for i in 1...7 {
            XCTAssertEqual(holes[i].position.x - holes[i - 1].position.x, 4, accuracy: 1e-6)
        }
        XCTAssertEqual(holes.last!.position.x, 29, accuracy: 1e-6)
    }

    func testMissingFixedLengthFallsBackToVariablePitch() {
        let line = LineShape(start: .zero, end: CGPoint(x: 29, y: 0))
        let walker = PathWalkerFactory.walker(for: .line(line))!
        let hybrid = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .hybrid, fixedLength: nil)
        let variable = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .variablePitch)

        XCTAssertEqual(hybrid.count, variable.count)
    }

    func testClosedPathIgnoresHybridSplit() {
        // A loop has no start for the split; hybrid degrades to the evened layout.
        let circle = EllipseShape(center: .zero, radiusX: 10, radiusY: 10)
        let walker = PathWalkerFactory.walker(for: .ellipse(circle))!
        let hybrid = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .hybrid, fixedLength: 10)
        let variable = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .variablePitch)

        XCTAssertEqual(hybrid.count, variable.count)
    }

    func testCorneredPathIgnoresHybrid() {
        // Cornered paths are always corner-anchored regardless of mode.
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        let hybrid = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .hybrid, fixedLength: 5)
        let fixed = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .fixedPitch)

        XCTAssertEqual(hybrid.count, fixed.count)
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)] {
            XCTAssertTrue(hybrid.contains { $0.position.distance(to: corner) < 1e-6 },
                          "corner \(corner) must keep its anchor hole")
        }
    }

    // MARK: - Persistence

    func testStitchLineFixedLengthRoundTripsThroughCodable() throws {
        let line = StitchLine(sourceShapeIds: [UUID()], ironId: UUID(), mode: .hybrid, fixedLength: 42.5)
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(StitchLine.self, from: data)
        XCTAssertEqual(decoded.mode, .hybrid)
        XCTAssertEqual(decoded.fixedLength ?? -1, 42.5, accuracy: 1e-9)
    }

    func testOldStitchLineWithoutFixedLengthDecodesAsNil() throws {
        let json = """
        {"id":"\(UUID().uuidString)","sourceShapeIds":["\(UUID().uuidString)"],
         "ironId":"\(UUID().uuidString)","mode":"fixedPitch","holes":[]}
        """
        let decoded = try JSONDecoder().decode(StitchLine.self, from: Data(json.utf8))
        XCTAssertNil(decoded.fixedLength)
    }

    // MARK: - Editor pick flow

    @MainActor
    func testHybridAutoStitchWaitsForPickAndClickCommits() {
        var doc = DocumentData.empty()
        let line = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        doc.layers[0].shapes = [.line(line)]
        let editor = EditorViewModel(document: doc)
        editor.selectedShapeIds = [line.id]
        editor.selectedStitchMode = .hybrid

        editor.autoStitchSelectedShape()
        XCTAssertTrue(editor.document.layers[0].stitchLines.isEmpty,
                      "an open smooth run waits for the split click")
        XCTAssertEqual(editor.pendingHybridRuns.count, 1)

        // Click near (52, 3): the cursor projects onto the path at 52mm.
        editor.handleClick(at: editor.transform.worldToScreen(CGPoint(x: 52, y: 3)))

        guard let stitch = editor.document.layers[0].stitchLines.first else {
            return XCTFail("expected a stitch line after the pick click")
        }
        XCTAssertEqual(stitch.mode, .hybrid)
        XCTAssertEqual(stitch.fixedLength ?? -1, 52, accuracy: 0.1)
        XCTAssertTrue(editor.pendingHybridRuns.isEmpty)
        XCTAssertNil(editor.hybridPickPreview)
    }

    @MainActor
    func testEscapeCancelsPendingPick() {
        var doc = DocumentData.empty()
        let line = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        doc.layers[0].shapes = [.line(line)]
        let editor = EditorViewModel(document: doc)
        editor.selectedShapeIds = [line.id]
        editor.selectedStitchMode = .hybrid

        editor.autoStitchSelectedShape()
        XCTAssertFalse(editor.pendingHybridRuns.isEmpty)

        editor.cancelDrawing()
        XCTAssertTrue(editor.pendingHybridRuns.isEmpty)
        XCTAssertTrue(editor.document.layers[0].stitchLines.isEmpty)
    }

    @MainActor
    func testHybridOnClosedShapeCommitsImmediately() {
        var doc = DocumentData.empty()
        let circle = EllipseShape(center: CGPoint(x: 50, y: 50), radiusX: 10, radiusY: 10)
        doc.layers[0].shapes = [.ellipse(circle)]
        let editor = EditorViewModel(document: doc)
        editor.selectedShapeIds = [circle.id]
        editor.selectedStitchMode = .hybrid

        editor.autoStitchSelectedShape()

        XCTAssertTrue(editor.pendingHybridRuns.isEmpty, "a closed run has no split to pick")
        guard let stitch = editor.document.layers[0].stitchLines.first else {
            return XCTFail("expected an immediate stitch line on the closed run")
        }
        XCTAssertEqual(stitch.mode, .hybrid)
        XCTAssertNil(stitch.fixedLength)
        XCTAssertFalse(stitch.holes.isEmpty)
    }

    @MainActor
    func testRegenerationPreservesFixedLength() {
        // In-place mirror regenerates the holes from the mirrored geometry; the
        // stored split point must survive so the fixed region follows the new start.
        var doc = DocumentData.empty()
        let line = LineShape(start: .zero, end: CGPoint(x: 100, y: 0))
        doc.layers[0].shapes = [.line(line)]
        let editor = EditorViewModel(document: doc)
        editor.selectedShapeIds = [line.id]
        editor.selectedStitchMode = .hybrid

        editor.autoStitchSelectedShape()
        editor.handleClick(at: editor.transform.worldToScreen(CGPoint(x: 20, y: 0)))
        XCTAssertEqual(editor.document.layers[0].stitchLines.first?.fixedLength ?? -1, 20, accuracy: 0.1)

        editor.mirrorSelectedShapes(.vertical, copy: false)

        guard let stitch = editor.document.layers[0].stitchLines.first else {
            return XCTFail("expected the stitch line to survive the mirror")
        }
        XCTAssertEqual(stitch.mode, .hybrid)
        XCTAssertEqual(stitch.fixedLength ?? -1, 20, accuracy: 0.1,
                       "the split point survives regeneration")
        XCTAssertEqual(stitch.holes.count,
                       AutoStitchEngine.generateHoles(
                           along: PathWalkerFactory.walker(for: editor.document.layers[0].shapes[0])!,
                           iron: editor.activePrickingIron!, mode: .hybrid, fixedLength: 20
                       ).count)
    }
}
