import XCTest
@testable import LCCAD

/// Box stitch (駒合わせ, #24): matching hole counts across two parts. Covers the
/// corner-constrained Even Count placement, the count estimators, and the matcher
/// that resolves a shared count from a policy.
final class BoxStitchTests: XCTestCase {

    private let iron = PrickingIron(name: "T", holeType: .diamond, pitch: 4)

    private func hasHole(_ holes: [StitchHole], near point: CGPoint, tolerance: CGFloat = 1e-6) -> Bool {
        holes.contains { $0.position.distance(to: point) < tolerance }
    }

    // MARK: - Corner-constrained Even Count placement

    func testClosedRectExactCountWithCornersAnchoredAndSidesEven() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 40, height: 40))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 12)

        XCTAssertEqual(holes.count, 12)
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 40, y: 40), CGPoint(x: 0, y: 40)] {
            XCTAssertTrue(hasHole(holes, near: corner), "corner \(corner) must keep its anchor hole")
        }
        // 8 interior holes over 4 equal sides = 2 per side, at thirds of each 40mm span.
        XCTAssertTrue(hasHole(holes, near: CGPoint(x: 40.0 / 3, y: 0)))
        XCTAssertTrue(hasHole(holes, near: CGPoint(x: 80.0 / 3, y: 0)))
    }

    func testCountEqualToAnchorsGivesCornersOnly() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 4)

        XCTAssertEqual(holes.count, 4)
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)] {
            XCTAssertTrue(hasHole(holes, near: corner))
        }
    }

    func testLongerSidesReceiveMoreInteriorHoles() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 60, height: 20))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 10)

        XCTAssertEqual(holes.count, 10)
        // 6 interior holes: the two 60mm sides must receive more than the two 20mm sides.
        let onLongSides = holes.filter { $0.position.y.magnitude < 1e-6 || abs($0.position.y - 20) < 1e-6 }
        let interiorOnLong = onLongSides.count - 4   // corners sit on both a long and a short side
        XCTAssertGreaterThan(interiorOnLong, 6 - interiorOnLong)
    }

    func testOpenCorneredPolylineHonorsCount() {
        let leg1 = AnyShape.line(LineShape(start: .zero, end: CGPoint(x: 10, y: 0)))
        let leg2 = AnyShape.line(LineShape(start: CGPoint(x: 10, y: 0), end: CGPoint(x: 10, y: 10)))
        let paths = StitchPathBuilder.build(from: [leg1, leg2])
        XCTAssertEqual(paths.count, 1, "the two legs must weld into one open run")
        let walker = paths[0].walker

        let five = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 5)
        XCTAssertEqual(five.count, 5)
        for point in [CGPoint.zero, CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0),
                      CGPoint(x: 10, y: 5), CGPoint(x: 10, y: 10)] {
            XCTAssertTrue(hasHole(five, near: point), "expected a hole at \(point)")
        }

        let anchorsOnly = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 3)
        XCTAssertEqual(anchorsOnly.count, 3, "both endpoints plus the corner")

        let clamped = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 2)
        XCTAssertEqual(clamped.count, 3, "count below the anchor count clamps up")
    }

    func testClosedLoopWithSeamMidEdgePlacesExactCountWithoutDuplicate() {
        // Square whose weld seam sits mid-edge: no corner at distance 0, and the last
        // span wraps across the seam. Perimeter 40, corners at distances 5/15/25/35.
        let walker = CompositePathWalker(segments: [
            LinePathWalker(start: CGPoint(x: 5, y: 0), end: CGPoint(x: 10, y: 0)),
            LinePathWalker(start: CGPoint(x: 10, y: 0), end: CGPoint(x: 10, y: 10)),
            LinePathWalker(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 0, y: 10)),
            LinePathWalker(start: CGPoint(x: 0, y: 10), end: CGPoint(x: 0, y: 0)),
            LinePathWalker(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 5, y: 0)),
        ], isClosed: true)

        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 8)
        XCTAssertEqual(holes.count, 8)
        for corner in [CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 0)] {
            XCTAssertTrue(hasHole(holes, near: corner))
        }
        XCTAssertTrue(hasHole(holes, near: CGPoint(x: 5, y: 0)), "the wrap span's midpoint crosses the seam")
        for i in 0..<holes.count {
            for j in (i + 1)..<holes.count {
                XCTAssertGreaterThan(holes[i].position.distance(to: holes[j].position), 1.0,
                                     "no two holes may coincide (seam duplicate)")
            }
        }
    }

    func testPlacementIsDeterministic() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 37, height: 13))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        let first = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 17)
        let second = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: 17)

        XCTAssertEqual(first.map(\.position), second.map(\.position))
        XCTAssertEqual(first.count, 17)
    }

    func testPitchModesOnCorneredPathAreUnchanged() {
        // Only Even Count with a count takes the new path; the pitch-driven modes keep
        // the corner-anchored ~pitch layout regardless of mode.
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let walker = PathWalkerFactory.walker(for: .rectangle(rect))!
        let fixed = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .fixedPitch)
        let variable = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .variablePitch)
        let noCount = AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: .evenCount, holeCount: nil)

        XCTAssertEqual(fixed.map(\.position), variable.map(\.position))
        XCTAssertEqual(fixed.map(\.position), noCount.map(\.position))
        XCTAssertEqual(fixed.count, 12, "10mm sides at 4mm pitch: 3 intervals per side")
    }

    // MARK: - Count estimators

    func testNaturalHoleCountMatchesPitchDrivenPlacement() {
        let circle = PathWalkerFactory.walker(for: .ellipse(EllipseShape(center: .zero, radiusX: 10, radiusY: 10)))!
        XCTAssertEqual(AutoStitchEngine.naturalHoleCount(along: circle, iron: iron), 16,
                       "2π·10 / 4 rounds to 16 evened holes")

        let rect = PathWalkerFactory.walker(for: .rectangle(RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))))!
        XCTAssertEqual(AutoStitchEngine.naturalHoleCount(along: rect, iron: iron), 12,
                       "matches the corner-anchored layout")
    }

    func testMinimumHoleCountPerPathKind() {
        let rect = PathWalkerFactory.walker(for: .rectangle(RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))))!
        XCTAssertEqual(AutoStitchEngine.minimumHoleCount(along: rect), 4)

        let legs = StitchPathBuilder.build(from: [
            .line(LineShape(start: .zero, end: CGPoint(x: 10, y: 0))),
            .line(LineShape(start: CGPoint(x: 10, y: 0), end: CGPoint(x: 10, y: 10))),
        ])
        XCTAssertEqual(AutoStitchEngine.minimumHoleCount(along: legs[0].walker), 3)

        let line = PathWalkerFactory.walker(for: .line(LineShape(start: .zero, end: CGPoint(x: 10, y: 0))))!
        XCTAssertEqual(AutoStitchEngine.minimumHoleCount(along: line), 2)

        let circle = PathWalkerFactory.walker(for: .ellipse(EllipseShape(center: .zero, radiusX: 10, radiusY: 10)))!
        XCTAssertEqual(AutoStitchEngine.minimumHoleCount(along: circle), 1)
    }

    // MARK: - Matcher

    func testPolicyResolution() {
        let proposal = BoxStitchProposal(naturalCountA: 44, naturalCountB: 16, minimumCount: 4)
        XCTAssertEqual(proposal.resolvedCount(for: .matchLarger), 44)
        XCTAssertEqual(proposal.resolvedCount(for: .matchSmaller), 16)
        XCTAssertEqual(proposal.resolvedCount(for: .custom(30)), 30)
    }

    func testResolvedCountClampsToSharedMinimum() {
        // A part with many corners can force the shared count above the other
        // part's natural count and above any custom request.
        let proposal = BoxStitchProposal(naturalCountA: 44, naturalCountB: 16, minimumCount: 20)
        XCTAssertEqual(proposal.resolvedCount(for: .matchSmaller), 20)
        XCTAssertEqual(proposal.resolvedCount(for: .custom(5)), 20)
        XCTAssertEqual(proposal.resolvedCount(for: .matchLarger), 44)
    }

    func testProposalRequiresExactlyTwoPaths() {
        let circle = AnyShape.ellipse(EllipseShape(center: .zero, radiusX: 10, radiusY: 10))
        let rect = AnyShape.rectangle(RectangleShape(origin: CGPoint(x: 40, y: 0), size: CGSize(width: 10, height: 10)))
        let extra = AnyShape.ellipse(EllipseShape(center: CGPoint(x: 80, y: 0), radiusX: 5, radiusY: 5))

        XCTAssertNil(BoxStitchMatcher.proposal(for: StitchPathBuilder.build(from: [circle]), iron: iron))
        XCTAssertNil(BoxStitchMatcher.proposal(for: StitchPathBuilder.build(from: [circle, rect, extra]), iron: iron))

        guard let proposal = BoxStitchMatcher.proposal(for: StitchPathBuilder.build(from: [circle, rect]), iron: iron) else {
            return XCTFail("two distinct contours must yield a proposal")
        }
        XCTAssertEqual(proposal.naturalCountA, 16)
        XCTAssertEqual(proposal.naturalCountB, 12)
        XCTAssertEqual(proposal.minimumCount, 4)
    }

    // MARK: - Editor pipeline

    @MainActor
    private func makeEditor(shapes: [AnyShape], selecting ids: [UUID]) -> EditorViewModel {
        var doc = DocumentData.empty()
        doc.layers[0].shapes = shapes
        let editor = EditorViewModel(document: doc)
        editor.selectedShapeIds = Set(ids)
        return editor
    }

    /// Circle (r=10, length ≈62.8) and a 10×10 rect (length 40): the default
    /// Diamond 4mm iron gives natural counts 16 and 12.
    @MainActor
    private func makeCircleAndRectEditor() -> (EditorViewModel, circle: AnyShape, rect: AnyShape) {
        let circle = AnyShape.ellipse(EllipseShape(center: .zero, radiusX: 10, radiusY: 10))
        let rect = AnyShape.rectangle(RectangleShape(origin: CGPoint(x: 40, y: 0), size: CGSize(width: 10, height: 10)))
        let editor = makeEditor(shapes: [circle, rect], selecting: [circle.id, rect.id])
        return (editor, circle, rect)
    }

    @MainActor
    func testBoxStitchRunsRequireExactlyTwoAndOrderLongerFirst() {
        let (editor, circle, rect) = makeCircleAndRectEditor()

        guard let runs = editor.boxStitchRuns() else { return XCTFail("two contours must resolve") }
        XCTAssertEqual(runs.a.sourceShapeIds, [circle.id], "A is the longer part")
        XCTAssertEqual(runs.b.sourceShapeIds, [rect.id])
        XCTAssertTrue(editor.canBoxStitch)

        editor.selectedShapeIds = [circle.id]
        XCTAssertNil(editor.boxStitchRuns())
        XCTAssertFalse(editor.canBoxStitch)
    }

    @MainActor
    func testBoxStitchEstimateReportsCountsPitchAndClamp() {
        let (editor, _, _) = makeCircleAndRectEditor()

        guard let larger = editor.boxStitchEstimate(policy: .matchLarger) else { return XCTFail() }
        XCTAssertEqual(larger.resolvedCount, 16)
        XCTAssertEqual(larger.runA.naturalCount, 16)
        XCTAssertEqual(larger.runB.naturalCount, 12)
        XCTAssertEqual(larger.runA.cornerCount, 0, "circle is smooth")
        XCTAssertEqual(larger.runB.cornerCount, 4, "normalized corner count for display")
        XCTAssertEqual(larger.runA.holes.count, 16)
        XCTAssertEqual(larger.runB.holes.count, 16)
        XCTAssertFalse(larger.wasClamped)
        XCTAssertTrue(larger.canApply)
        XCTAssertEqual(larger.runA.effectivePitch, 20 * .pi / 16, accuracy: 0.01)
        XCTAssertEqual(larger.runB.effectivePitch, 40.0 / 16, accuracy: 1e-6)

        guard let clamped = editor.boxStitchEstimate(policy: .custom(3)) else { return XCTFail() }
        XCTAssertEqual(clamped.requestedCount, 3)
        XCTAssertEqual(clamped.resolvedCount, 4, "the rect's 4 corner anchors set the floor")
        XCTAssertTrue(clamped.wasClamped)
    }

    @MainActor
    func testApplyBoxStitchCommitsTwoMatchedPersistedLines() {
        let (editor, _, rect) = makeCircleAndRectEditor()

        editor.applyBoxStitch(count: 16)

        let lines = editor.document.layers[0].stitchLines
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            XCTAssertEqual(line.mode, .evenCount)
            XCTAssertEqual(line.holeCount, 16)
            XCTAssertEqual(line.holes.count, 16)
        }
        let rectLine = lines.first { $0.sourceShapeIds == [rect.id] }!
        XCTAssertTrue(hasHole(rectLine.holes, near: CGPoint(x: 40, y: 0)), "rect corners stay anchored")
    }

    @MainActor
    func testApplyBoxStitchReplacesExistingLinesOnTheSameRuns() {
        let (editor, _, rect) = makeCircleAndRectEditor()

        // Pre-existing pitch-driven stitch on the rect alone.
        editor.selectedShapeIds = [rect.id]
        editor.autoStitchSelectedShape()
        XCTAssertEqual(editor.document.layers[0].stitchLines.count, 1)

        editor.selectedShapeIds = Set(editor.document.layers[0].shapes.map(\.id))
        guard let estimate = editor.boxStitchEstimate(policy: .matchLarger) else { return XCTFail() }
        XCTAssertTrue(estimate.runB.hasExistingStitchLine)
        XCTAssertFalse(estimate.runA.hasExistingStitchLine)

        editor.applyBoxStitch(count: 16)
        let lines = editor.document.layers[0].stitchLines
        XCTAssertEqual(lines.count, 2, "the old rect line is replaced, not duplicated")
        XCTAssertTrue(lines.allSatisfy { $0.holeCount == 16 })
    }

    @MainActor
    func testApplyBoxStitchReportsWhetherItCommitted() {
        let (editor, _, _) = makeCircleAndRectEditor()

        XCTAssertTrue(editor.applyBoxStitch(count: 16))

        // A selection change while the sheet was up (e.g. via undo) makes the
        // re-derived runs unresolvable — the apply must report the failure.
        editor.selectedShapeIds = []
        XCTAssertFalse(editor.applyBoxStitch(count: 16))
        XCTAssertEqual(editor.document.layers[0].stitchLines.count, 2, "failed apply must not mutate")
    }

    @MainActor
    func testUndoRemovesBothCommittedLines() {
        let (editor, _, _) = makeCircleAndRectEditor()
        let undo = UndoManager()
        editor.undoManager = undo

        editor.applyBoxStitch(count: 16)
        XCTAssertEqual(editor.document.layers[0].stitchLines.count, 2)

        undo.undo()
        XCTAssertTrue(editor.document.layers[0].stitchLines.isEmpty, "one undo restores everything")
    }

    @MainActor
    func testRegenerationAfterEditKeepsMatchedCounts() {
        let (editor, _, rect) = makeCircleAndRectEditor()
        editor.applyBoxStitch(count: 16)

        // Mirroring deforms through the regeneration path (not a rigid translate);
        // the persisted holeCount must survive on the cornered run.
        editor.selectedShapeIds = [rect.id]
        editor.mirrorSelectedShapes(.vertical, copy: false)

        let lines = editor.document.layers[0].stitchLines
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            XCTAssertEqual(line.mode, .evenCount)
            XCTAssertEqual(line.holes.count, 16, "both parts stay matched after the edit")
        }
    }
}
