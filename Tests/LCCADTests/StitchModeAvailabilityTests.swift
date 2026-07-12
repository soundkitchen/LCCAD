import XCTest
@testable import LCCAD

/// `EditorViewModel.stitchModeAffectsSelection` drives whether the Mode picker in the
/// Stitch Settings panel is enabled. Fixed/Variable only differ on open paths without
/// corners; corner-anchored and closed smooth paths are always evenly spaced (issue #32).
@MainActor
final class StitchModeAvailabilityTests: XCTestCase {

    private func makeEditor(shapes: [AnyShape], selecting ids: [UUID]) -> EditorViewModel {
        var doc = DocumentData.empty()
        doc.layers[0].shapes = shapes
        let editor = EditorViewModel(document: doc)
        editor.selectedShapeIds = Set(ids)
        return editor
    }

    // MARK: - Mode matters: open smooth paths

    func testOpenLineEnablesMode() {
        let line = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))
        let editor = makeEditor(shapes: [.line(line)], selecting: [line.id])
        XCTAssertTrue(editor.stitchModeAffectsSelection)
    }

    func testOpenArcEnablesMode() {
        let arc = ArcShape(center: .zero, radius: 10, startAngle: 0, endAngle: .pi)
        let editor = makeEditor(shapes: [.arc(arc)], selecting: [arc.id])
        XCTAssertTrue(editor.stitchModeAffectsSelection)
    }

    func testMixedSelectionWithOpenLineEnablesMode() {
        // A rectangle alone ignores the mode, but the standalone open line still honors it.
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let line = LineShape(start: CGPoint(x: 20, y: 0), end: CGPoint(x: 30, y: 0))
        let editor = makeEditor(shapes: [.rectangle(rect), .line(line)], selecting: [rect.id, line.id])
        XCTAssertTrue(editor.stitchModeAffectsSelection)
    }

    func testGroupedOpenLineEnablesMode() {
        let line = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))
        let group = GroupShape(children: [.line(line)])
        let editor = makeEditor(shapes: [.group(group)], selecting: [group.id])
        XCTAssertTrue(editor.stitchModeAffectsSelection)
    }

    func testOpenSmoothMultiSegmentBezierEnablesMode() {
        // Two cubic segments joined tangent-continuously (collinear handles at the middle
        // anchor): a CompositePathWalker with no detected corners, so the mode applies.
        let bezier = BezierShape(points: [
            BezierPoint(point: CGPoint(x: 0, y: 0), controlIn: CGPoint(x: 0, y: 0), controlOut: CGPoint(x: 3, y: 0)),
            BezierPoint(point: CGPoint(x: 10, y: 5), controlIn: CGPoint(x: 7, y: 5), controlOut: CGPoint(x: 13, y: 5)),
            BezierPoint(point: CGPoint(x: 20, y: 10), controlIn: CGPoint(x: 17, y: 10), controlOut: CGPoint(x: 20, y: 10)),
        ], isClosed: false)
        let editor = makeEditor(shapes: [.bezier(bezier)], selecting: [bezier.id])
        XCTAssertTrue(editor.stitchModeAffectsSelection)
    }

    func testTangentWeldedLineAndArcEnablesMode() {
        // Line into an arc that leaves tangent to it (same geometry as the smooth-joint
        // walker test): welded into one open run whose joint stays under the 5° corner
        // threshold, so the mode still applies.
        let line = LineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 0))
        let arc = ArcShape(center: CGPoint(x: 10, y: 5), radius: 5,
                           startAngle: -.pi / 2, endAngle: 0, clockwise: false)
        let editor = makeEditor(shapes: [.line(line), .arc(arc)], selecting: [line.id, arc.id])
        XCTAssertTrue(editor.stitchModeAffectsSelection)
    }

    // MARK: - Mode has no effect: corners or closed paths

    func testRectangleDisablesMode() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10, height: 10))
        let editor = makeEditor(shapes: [.rectangle(rect)], selecting: [rect.id])
        XCTAssertFalse(editor.stitchModeAffectsSelection)
    }

    func testCircleDisablesMode() {
        let circle = EllipseShape(center: .zero, radiusX: 10, radiusY: 10)
        let editor = makeEditor(shapes: [.ellipse(circle)], selecting: [circle.id])
        XCTAssertFalse(editor.stitchModeAffectsSelection)
    }

    func testWeldedClosedLoopDisablesMode() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        let lines = (0..<4).map { LineShape(start: pts[$0], end: pts[($0 + 1) % 4]) }
        let editor = makeEditor(shapes: lines.map { .line($0) }, selecting: lines.map(\.id))
        XCTAssertFalse(editor.stitchModeAffectsSelection)
    }

    func testOpenCorneredPolylineDisablesMode() {
        // Two welded lines meeting at a right angle: open, but corner-anchored.
        let l1 = LineShape(start: .zero, end: CGPoint(x: 10, y: 0))
        let l2 = LineShape(start: CGPoint(x: 10, y: 0), end: CGPoint(x: 10, y: 10))
        let editor = makeEditor(shapes: [.line(l1), .line(l2)], selecting: [l1.id, l2.id])
        XCTAssertFalse(editor.stitchModeAffectsSelection)
    }

    // MARK: - Degenerate selections

    func testEmptySelectionKeepsModeEnabled() {
        let editor = makeEditor(shapes: [], selecting: [])
        XCTAssertTrue(editor.stitchModeAffectsSelection)
    }

    func testNonStitchableSelectionKeepsModeEnabled() {
        let text = TextShape(position: .zero, content: "label")
        let editor = makeEditor(shapes: [.text(text)], selecting: [text.id])
        XCTAssertTrue(editor.stitchModeAffectsSelection)
    }
}
