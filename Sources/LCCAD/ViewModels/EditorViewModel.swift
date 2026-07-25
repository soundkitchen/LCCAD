import SwiftUI
import Observation

// MARK: - FocusedValue Key for accessing editor from menu commands

struct FocusedEditorKey: FocusedValueKey {
    typealias Value = EditorViewModel
}

extension FocusedValues {
    var editor: EditorViewModel? {
        get { self[FocusedEditorKey.self] }
        set { self[FocusedEditorKey.self] = newValue }
    }
}

enum DrawingTool: String, CaseIterable, Sendable {
    case select = "Select"
    case line = "Line"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case arc = "Arc"
    case bezier = "Bezier"
    case text = "Text"
    case dimensionLine = "Dimension"
    // Editing tools
    case offset = "Offset"
    case trim = "Trim"
    case bevel = "Bevel"
    // Layout tools
    case page = "Page"

    var iconName: String {
        switch self {
        case .select: return "cursorarrow"
        case .line: return "minus"
        case .rectangle: return "square"
        case .ellipse: return "circle"
        case .arc: return "circle.and.line.horizontal"
        case .bezier: return "point.topleft.down.to.point.bottomright.curvepath"
        case .text: return "character"
        case .dimensionLine: return "ruler"
        case .offset: return "square.inset.filled"
        case .trim: return "scissors"
        case .bevel: return "app"
        case .page: return "doc.plaintext"
        }
    }

    /// Single-key shortcut for this tool, or nil if none is assigned.
    /// Must stay in sync with CanvasView.onKeyPress.
    var shortcutKey: String? {
        switch self {
        case .select: return "V"
        case .line: return "L"
        case .rectangle: return "R"
        case .ellipse: return "E"
        case .arc: return "A"
        case .bezier: return "P"
        case .text: return "T"
        case .dimensionLine: return "D"
        case .offset, .trim, .bevel, .page: return nil
        }
    }

    /// Tooltip text including the shortcut key when available.
    var tooltip: String {
        if let key = shortcutKey {
            return "\(rawValue) (\(key))"
        }
        return rawValue
    }

    /// The first 8 cases are drawing tools, the rest are editing tools
    static var drawingTools: [DrawingTool] { [.select, .line, .rectangle, .ellipse, .arc, .bezier, .text, .dimensionLine] }
    static var editingTools: [DrawingTool] { [.offset, .trim, .bevel] }
    static var layoutTools: [DrawingTool] { [.page] }
}

enum DragPhase {
    case changed
    case ended
}

enum BezierDragTarget: Sendable {
    case anchor
    case controlIn
    case controlOut
}

/// Represents the in-progress drawing preview shown while the user is creating a shape.
enum DrawingPreview: Sendable {
    case lineFromClick(start: CGPoint, end: CGPoint)
    case lineFromDrag(start: CGPoint, end: CGPoint)
    case rectangle(origin: CGPoint, size: CGSize)
    case ellipsePreview(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat)
    case arcPreview(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool)
    case bezierPreview(points: [BezierPoint], currentPoint: CGPoint)
    case startPoint(CGPoint)
    case twoPoints(CGPoint, CGPoint)
    case dimensionPreview(DimensionLineShape)
}

/// Ghost-hole payload for the box stitch (駒合わせ) sheet: while the sheet is up the
/// canvas renders these semi-transparent so the user can judge the layout before Apply.
struct BoxStitchPreview: Sendable {
    var holesA: [StitchHole]
    var holesB: [StitchHole]
    var holeType: HoleType
    var holeSize: CGFloat
}

/// Ghost payload while a hybrid split-point pick (#23c) is pending: the holes a click
/// at the current cursor would commit, plus the split marker geometry.
struct HybridPickPreview: Sendable {
    var holes: [StitchHole]
    var splitPoint: CGPoint
    /// Path tangent at the split point (radians) — the marker tick sits perpendicular.
    var splitAngle: CGFloat
    var holeType: HoleType
    var holeSize: CGFloat
}

/// Non-mutating dry run of a box stitch: what both parts would receive for a given
/// policy. Drives the sheet's labels, warnings, Apply gating, and the ghost preview.
struct BoxStitchEstimate: Sendable {
    struct Run: Sendable {
        let length: CGFloat
        let isClosed: Bool
        let cornerCount: Int
        let naturalCount: Int
        let holes: [StitchHole]
        let effectivePitch: CGFloat
        let hasExistingStitchLine: Bool
        let sourceShapeIds: [UUID]
    }

    let runA: Run
    let runB: Run
    /// The count the policy asked for, before clamping to the parts' anchor minimum.
    let requestedCount: Int
    /// The count actually placed on both parts.
    let resolvedCount: Int
    var wasClamped: Bool { resolvedCount != requestedCount }
    var canApply: Bool {
        !runA.holes.isEmpty && runA.holes.count == runB.holes.count
    }
}

@Observable
@MainActor
final class EditorViewModel {
    var document: DocumentData {
        didSet { fileDocument?.data = document }
    }
    var transform: CanvasTransform = CanvasTransform()
    var currentTool: DrawingTool = .select
    var selectedShapeIds: Set<UUID> = []
    var cursorWorldPosition: CGPoint = .zero
    var activeLayerIndex: Int = 0 {
        didSet {
            // Switching the target layer mid-pick would commit the stitch to a layer
            // the user wasn't looking at when they started Auto Stitch; drop the pick.
            if oldValue != activeLayerIndex {
                pendingHybridRuns = []
                hybridPickPreview = nil
            }
        }
    }

    // Marquee selection
    var marqueeStart: CGPoint?
    var marqueeRect: CGRect?

    // MARK: - Selection Helpers

    /// Convenience: the single selected shape ID when exactly one shape is selected.
    var selectedShapeId: UUID? {
        selectedShapeIds.count == 1 ? selectedShapeIds.first : nil
    }

    var hasSelection: Bool { !selectedShapeIds.isEmpty }
    var isSingleSelection: Bool { selectedShapeIds.count == 1 }
    var isMultiSelection: Bool { selectedShapeIds.count > 1 }

    /// All currently selected shapes.
    var selectedShapes: [AnyShape] {
        selectedShapeIds.compactMap { findShape(id: $0) }
    }

    /// Combined bounding box of all selected shapes.
    var selectionBoundingBox: CGRect? {
        let shapes = selectedShapes
        guard let first = shapes.first else { return nil }
        var combined = first.boundingBox
        for shape in shapes.dropFirst() {
            combined = combined.union(shape.boundingBox)
        }
        return combined
    }

    /// Combined visual bounding box of all selected shapes — tight to rendered ink.
    /// Used by Mirror Copy so the duplicate sits flush against the visible edge,
    /// not against handle or full-circle padding.
    var selectionVisualBoundingBox: CGRect? {
        let shapes = selectedShapes
        guard let first = shapes.first else { return nil }
        var combined = first.visualBoundingBox
        for shape in shapes.dropFirst() {
            combined = combined.union(shape.visualBoundingBox)
        }
        return combined
    }

    // Drag state
    var lastPanTranslation: CGSize?
    var dragStartWorldPoint: CGPoint?

    // Arc tool: 3-click state (start → end → bulge)
    var arcSecondPoint: CGPoint?
    var dimensionSecondPoint: CGPoint?
    /// Dimension kind used when drawing new dimension lines.
    var currentDimensionKind: DimensionKind = .aligned

    // Bezier tool: accumulated points
    var bezierPoints: [BezierPoint] = []
    var isDraggingBezierHandle: Bool = false

    // Bezier point editing (post-creation)
    var draggingBezierPointIndex: Int?
    var draggingBezierTarget: BezierDragTarget?
    var bezierEditUndoSnapshot: DocumentData?

    // Move undo support
    var moveUndoSnapshot: DocumentData?

    // Select-tool drag move state — cursor world point at drag start (raw, unsnapped),
    // selection bounding box at drag start (used to anchor snap on shape reference points
    // rather than the cursor), and the cumulative delta already applied this drag.
    var moveDragStartCursorWorld: CGPoint?
    var moveDragSelectionBBox: CGRect?
    var moveAccumulatedDelta: CGPoint = .zero

    // Drawing preview
    var drawingPreview: DrawingPreview?

    // Snap state
    var activeSnapCandidate: SnapCandidate?

    // Canvas size (updated by CanvasView via GeometryReader)
    var canvasSize: CGSize = CGSize(width: 800, height: 600)

    // Page layout state
    var selectedPageId: UUID?
    var pageMoveUndoSnapshot: DocumentData?
    var pageDragRawOrigin: CGPoint?

    // Stitch state
    var selectedIronId: UUID?
    var selectedStitchMode: StitchMode = .fixedPitch
    /// Hole count used by `.evenCount` mode (per run in the selection).
    var selectedStitchHoleCount: Int = 10
    var showPrickingIronSheet: Bool = false

    // Box stitch (駒合わせ) state
    var showBoxStitchSheet: Bool = false
    /// Ghost holes rendered while the box stitch sheet is up; cleared on dismiss.
    var boxStitchPreview: BoxStitchPreview?

    // Hybrid stitch (#23c) state
    /// Open smooth runs awaiting the hybrid split-point click; non-empty puts the
    /// canvas into pick mode (click commits the nearest run, Escape cancels the rest).
    var pendingHybridRuns: [StitchPathBuilder.StitchPath] = []
    /// Ghost holes + split marker following the cursor while a pick is pending.
    var hybridPickPreview: HybridPickPreview?

    // Array sheet state
    var showArraySheet: Bool = false

    // Bevel state — shared radius (mm) used by both the click tool and the bulk sheet.
    var bevelRadius: CGFloat = 2.0
    var showBevelSheet: Bool = false

    // Template state
    /// Presents the "save selection as template" sheet.
    var showSaveTemplateSheet: Bool = false
    /// When non-nil, the next canvas click places this template (click-to-place mode).
    var pendingTemplate: Template?

    var activePrickingIron: PrickingIron? {
        if let id = selectedIronId {
            return document.prickingIrons.first { $0.id == id }
        }
        return document.prickingIrons.first
    }

    // Edge scroll state
    private var edgeScrollTimer: Timer?
    private var edgeScrollDelta: CGPoint = .zero
    private let edgeMargin: CGFloat = 60
    private let edgeScrollSpeedMin: CGFloat = 0.5   // world mm per tick (margin boundary)
    private let edgeScrollSpeedMax: CGFloat = 4.0   // world mm per tick (canvas edge)

    // Document binding
    weak var fileDocument: LCCADFileDocument?
    var undoManager: UndoManager?

    init(document: DocumentData = .empty()) {
        self.document = document
    }

    // MARK: - Edge Scroll

    /// Call on every drag update to evaluate whether edge scrolling should start/stop.
    func updateEdgeScroll(cursorScreenPoint: CGPoint, canvasSize: CGSize) {
        var delta = CGPoint.zero

        if cursorScreenPoint.x < edgeMargin {
            let t = 1.0 - cursorScreenPoint.x / edgeMargin  // 0 at boundary, 1 at edge
            delta.x = edgeScrollSpeedMin + (edgeScrollSpeedMax - edgeScrollSpeedMin) * t
        } else if cursorScreenPoint.x > canvasSize.width - edgeMargin {
            let t = 1.0 - (canvasSize.width - cursorScreenPoint.x) / edgeMargin
            delta.x = -(edgeScrollSpeedMin + (edgeScrollSpeedMax - edgeScrollSpeedMin) * t)
        }

        if cursorScreenPoint.y < edgeMargin {
            let t = 1.0 - cursorScreenPoint.y / edgeMargin
            delta.y = edgeScrollSpeedMin + (edgeScrollSpeedMax - edgeScrollSpeedMin) * t
        } else if cursorScreenPoint.y > canvasSize.height - edgeMargin {
            let t = 1.0 - (canvasSize.height - cursorScreenPoint.y) / edgeMargin
            delta.y = -(edgeScrollSpeedMin + (edgeScrollSpeedMax - edgeScrollSpeedMin) * t)
        }

        edgeScrollDelta = delta

        if delta.x != 0 || delta.y != 0 {
            if edgeScrollTimer == nil {
                let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.performEdgeScrollTick()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                edgeScrollTimer = timer
            }
        } else {
            stopEdgeScroll()
        }
    }

    func stopEdgeScroll() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
        edgeScrollDelta = .zero
    }

    private func performEdgeScrollTick() {
        let d = edgeScrollDelta
        guard d.x != 0 || d.y != 0 else { return }

        // Pan the canvas
        let screenDelta = CGPoint(x: d.x * transform.scale, y: d.y * transform.scale)
        transform.pan(by: screenDelta)

        // Move the selected shapes in the opposite world direction
        // so they track with the cursor position (skip during bezier point drag).
        // This fires only mid-drag (edge scroll), so park stitch welds until commit.
        if hasSelection && draggingBezierPointIndex == nil {
            moveSelectedShapes(by: CGPoint(x: -d.x, y: -d.y), live: true)
        }
    }

    // MARK: - Layer Access

    /// Index clamped into the valid range, so a stale `activeLayerIndex` left over
    /// from a larger document (e.g. after New/Open) can't index out of bounds.
    private var safeActiveLayerIndex: Int {
        min(max(activeLayerIndex, 0), max(document.layers.count - 1, 0))
    }

    var activeLayer: Layer {
        get { document.layers[safeActiveLayerIndex] }
        set { document.layers[safeActiveLayerIndex] = newValue }
    }

    // MARK: - Undo Support

    private func registerUndo(actionName: String, oldDocument: DocumentData) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            let redoDoc = target.document
            target.document = oldDocument
            // Undo/redo swaps the document out from under a pending hybrid pick; the
            // parked walkers would go stale against the restored geometry, so a later
            // click could commit holes for shapes that no longer match. Drop the pick.
            target.pendingHybridRuns = []
            target.hybridPickPreview = nil
            target.registerUndo(actionName: actionName, oldDocument: redoDoc)
        }
        undoManager.setActionName(actionName)
    }

    private func addShapeWithUndo(_ shape: AnyShape, actionName: String) {
        let old = document
        activeLayer.shapes.append(shape)
        registerUndo(actionName: actionName, oldDocument: old)
    }

    func commitMoveWithUndo(oldDocument: DocumentData) {
        // A live drag parks partially-moved stitch runs (see `translateStitchHoles(live:)`):
        // their holes stay put during the gesture so the run is not destroyed mid-drag.
        // Now the drag is over, settle the weld decision against the final geometry. (#33)
        finalizeStitchHoleWeld(forShapeIds: selectedShapeIdsWithDescendants())
        guard oldDocument != document else { return }
        registerUndo(actionName: "Move Shape", oldDocument: oldDocument)
    }

    /// The current selection expanded to include group descendants — the id space stitch
    /// lines are keyed against (`sourceShapeIds`). Used where we need the moved-id set
    /// without translating; the drag/position movers fold the same collection into their
    /// translate pass to avoid a second `findShapeLocation` sweep in the per-frame hot path.
    private func selectedShapeIdsWithDescendants() -> Set<UUID> {
        var ids: Set<UUID> = []
        for id in selectedShapeIds {
            if let (li, si) = findShapeLocation(id: id) {
                ids.formUnion(collectShapeIds(in: document.layers[li].shapes[si]))
            }
        }
        return ids
    }

    // MARK: - Position Editing

    /// Move the selected shape(s) so the selection bounding box origin equals the given world position (mm).
    func setSelectedShapePosition(x: CGFloat?, y: CGFloat?) {
        guard let bbox = selectionBoundingBox else { return }
        let current = bbox.origin
        let dx = (x ?? current.x) - current.x
        let dy = (y ?? current.y) - current.y
        guard dx != 0 || dy != 0 else { return }
        let old = document
        let delta = CGPoint(x: dx, y: dy)
        var movedIds: Set<UUID> = []
        for id in selectedShapeIds {
            if let (li, si) = findShapeLocation(id: id) {
                movedIds.formUnion(collectShapeIds(in: document.layers[li].shapes[si]))
                document.layers[li].shapes[si].translate(by: delta)
            }
        }
        translateStitchHoles(forShapeIds: movedIds, by: delta)
        registerUndo(actionName: "Move Shape", oldDocument: old)
    }

    // MARK: - Stitch Hole Follow-Through

    /// Collect an id plus the ids of any descendants (for groups).
    /// Stitch lines reference shapes by `sourceShapeId`; when a group is translated,
    /// holes keyed to its children must move too.
    private func collectShapeIds(in shape: AnyShape) -> Set<UUID> {
        var ids: Set<UUID> = [shape.id]
        if case .group(let group) = shape {
            for child in group.children {
                ids.formUnion(collectShapeIds(in: child))
            }
        }
        return ids
    }

    /// Flatten a shape into its leaf shapes, recursing into groups. Used to feed the
    /// stitch path builder, which decides per leaf what is stitchable.
    private func leafShapes(of shape: AnyShape) -> [AnyShape] {
        if case .group(let group) = shape {
            return group.children.flatMap { leafShapes(of: $0) }
        }
        return [shape]
    }

    /// Walk every stitch line whose source shapes intersect `ids`, in document order.
    /// `resolve(li, si)` handles the matched line and returns the next index to examine —
    /// `si + 1` to advance, or the same `si` after a `remove(at:)`. Centralizing the scan
    /// keeps the (match condition + delete-safe iteration) contract in one place across the
    /// move / finalize / regenerate paths.
    private func forEachStitchLine(touching ids: Set<UUID>, _ resolve: (_ layer: Int, _ index: Int) -> Int) {
        for li in document.layers.indices {
            var si = 0
            while si < document.layers[li].stitchLines.count {
                if document.layers[li].stitchLines[si].sourceShapeIds.contains(where: ids.contains) {
                    si = resolve(li, si)
                } else {
                    si += 1
                }
            }
        }
    }

    /// Keep stitch holes following moved shapes.
    /// - A line whose **every** source moved is shifted rigidly by `delta` (fast path).
    /// - A line whose sources only **partially** moved is deformed, so it is regenerated
    ///   from current geometry (and dropped if the run no longer welds into one path).
    ///
    /// During a live drag (`live: true`) the partial case is **not** resolved each frame:
    /// the holes are parked in place and the weld decision is deferred to drag-commit
    /// (`finalizeStitchHoleWeld`). That keeps a run alive even if it momentarily breaks
    /// weld — then returns to a welded position in the same gesture — and avoids the
    /// per-frame regenerate cost. (#33)
    private func translateStitchHoles(forShapeIds ids: Set<UUID>, by delta: CGPoint, live: Bool = false) {
        guard !ids.isEmpty, delta.x != 0 || delta.y != 0 else { return }
        forEachStitchLine(touching: ids) { li, si in
            let sources = document.layers[li].stitchLines[si].sourceShapeIds
            if sources.allSatisfy({ ids.contains($0) }) {
                for hi in document.layers[li].stitchLines[si].holes.indices {
                    document.layers[li].stitchLines[si].holes[hi].position.x += delta.x
                    document.layers[li].stitchLines[si].holes[hi].position.y += delta.y
                }
                return si + 1
            } else if live {
                return si + 1   // park; resolved at drag-commit
            } else {
                return resolvePartialStitchLine(layer: li, index: si)
            }
        }
    }

    /// Apply the partial-move weld decision to the stitch line at `[layer][index]`: a run
    /// whose sources moved only partially is deformed, so regenerate its holes from the
    /// current geometry — or **drop** the line if the segments no longer weld into one path.
    ///
    /// A missing iron also **drops** the line here. This intentionally differs from
    /// `regenerateStitchLines`, which instead *preserves* the existing holes when only the
    /// iron is gone (stale but recoverable). The asymmetry is pre-existing — carried over
    /// from the inline move code — so keep the two contracts distinct if they are ever
    /// unified. Returns the next index to examine.
    private func resolvePartialStitchLine(layer li: Int, index si: Int) -> Int {
        let line = document.layers[li].stitchLines[si]
        if let walker = weldedWalker(forShapeIds: line.sourceShapeIds),
           let iron = document.prickingIrons.first(where: { $0.id == line.ironId }) {
            document.layers[li].stitchLines[si].holes =
                AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: line.mode,
                                               holeCount: line.holeCount, fixedLength: line.fixedLength)
            return si + 1
        } else {
            document.layers[li].stitchLines.remove(at: si)
            return si
        }
    }

    /// Settle the weld decision for stitch runs that were parked during a live drag.
    /// Only partially-moved runs were parked (`translateStitchHoles(live:)`); fully-moved
    /// runs were rigidly shifted frame-by-frame and stay welded, so they need no work.
    /// Run once at drag-commit. (#33)
    private func finalizeStitchHoleWeld(forShapeIds ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        forEachStitchLine(touching: ids) { li, si in
            // Fully-moved runs were rigidly shifted frame-by-frame and stay welded; only
            // the partially-moved runs were parked, so only those need settling here.
            guard !document.layers[li].stitchLines[si].sourceShapeIds.allSatisfy({ ids.contains($0) })
            else { return si + 1 }
            return resolvePartialStitchLine(layer: li, index: si)
        }
    }

    /// Regenerate the holes of every stitch line whose `sourceShapeId` is in `ids`,
    /// using the shape's current geometry. Called after a deformation operation
    /// (bezier handle drag, bevel, trim) so that holes track the new path.
    ///
    /// - Source shape missing or non-walkable → drop the stitch line.
    /// - Iron missing → leave the holes as-is (preserve user data; stale but recoverable
    ///   by re-adding the iron and running auto-stitch again).
    private func regenerateStitchLines(forShapeIds ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        forEachStitchLine(touching: ids) { li, si in
            let line = document.layers[li].stitchLines[si]
            guard let walker = weldedWalker(forShapeIds: line.sourceShapeIds) else {
                document.layers[li].stitchLines.remove(at: si)
                return si
            }
            // Iron missing → keep the (stale) holes; preserve user data, recoverable later.
            if let iron = document.prickingIrons.first(where: { $0.id == line.ironId }) {
                document.layers[li].stitchLines[si].holes =
                    AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: line.mode,
                                                   holeCount: line.holeCount, fixedLength: line.fixedLength)
            }
            return si + 1
        }
    }

    /// Rebuild the walkable path for an existing stitch line from its current source
    /// shapes, re-running the weld so a multi-segment outline tracks edits to any of
    /// its segments. Returns nil when a source shape is gone or the segments no longer
    /// form a single connected run (the caller drops the line in that case).
    private func weldedWalker(forShapeIds ids: [UUID]) -> PathWalkable? {
        let shapes = ids.compactMap { findShapeRecursive(id: $0) }
        guard shapes.count == ids.count else { return nil }
        let paths = StitchPathBuilder.build(from: shapes)
        guard paths.count == 1 else { return nil }
        return paths[0].walker
    }

    /// After an operation replaces a shape (e.g. bevel turns a corner into shortened
    /// edges + a fillet arc), rewrite the `sourceShapeIds` of affected stitch lines: drop
    /// `removed` ids and add `added` ids, so the welded run can be rebuilt over the new
    /// shapes. Caller follows up with `regenerateStitchLines`.
    ///
    /// Only lines whose sources contain **all** of `anchors` are rewritten. For a line
    /// bevel that means the single run threading through *both* edges of the corner — a
    /// stitch line following only one edge (or a separate per-edge line) is left alone so
    /// the fillet arc isn't double-counted onto it.
    private func remapStitchLineSources(containingAll anchors: Set<UUID>, removing removed: Set<UUID>, adding added: [UUID]) {
        for li in document.layers.indices {
            for si in document.layers[li].stitchLines.indices {
                var ids = document.layers[li].stitchLines[si].sourceShapeIds
                guard anchors.allSatisfy({ ids.contains($0) }) else { continue }
                ids.removeAll { removed.contains($0) }
                for newId in added where !ids.contains(newId) { ids.append(newId) }
                document.layers[li].stitchLines[si].sourceShapeIds = ids
            }
        }
    }

    // MARK: - Stroke Property Editing

    func updateStroke(_ update: (inout StrokeStyle) -> Void) {
        guard hasSelection else { return }
        let old = document
        for id in selectedShapeIds {
            if let (li, si) = findShapeLocation(id: id) {
                var stroke = document.layers[li].shapes[si].stroke
                update(&stroke)
                document.layers[li].shapes[si].stroke = stroke
            }
        }
        registerUndo(actionName: "Edit Stroke", oldDocument: old)
    }

    // MARK: - Text Property Editing

    func updateTextProperty(_ update: (inout TextShape) -> Void) {
        // For text editing, use the single selected shape (text editing requires single selection)
        guard let id = selectedShapeIds.first,
              let (li, si) = findShapeLocation(id: id),
              case .text(var text) = document.layers[li].shapes[si] else { return }
        let old = document
        update(&text)
        document.layers[li].shapes[si] = .text(text)
        registerUndo(actionName: "Edit Text", oldDocument: old)
    }

    /// Edit the currently selected dimension line with undo registration.
    func updateDimensionProperty(_ update: (inout DimensionLineShape) -> Void) {
        guard let id = selectedShapeIds.first,
              let (li, si) = findShapeLocation(id: id),
              case .dimensionLine(var dim) = document.layers[li].shapes[si] else { return }
        let old = document
        update(&dim)
        document.layers[li].shapes[si] = .dimensionLine(dim)
        registerUndo(actionName: "Edit Dimension", oldDocument: old)
    }

    // MARK: - Bezier Point Editing

    func bezierPointHitTest(worldPoint: CGPoint, shape: BezierShape, tolerance: CGFloat) -> (pointIndex: Int, target: BezierDragTarget)? {
        var best: (pointIndex: Int, target: BezierDragTarget, distance: CGFloat)?

        for (i, bp) in shape.points.enumerated() {
            // Check controlIn
            if bp.controlIn != bp.point {
                let dist = worldPoint.distance(to: bp.controlIn)
                if dist <= tolerance {
                    if best == nil || dist < best!.distance {
                        best = (i, .controlIn, dist)
                    }
                }
            }
            // Check controlOut
            if bp.controlOut != bp.point {
                let dist = worldPoint.distance(to: bp.controlOut)
                if dist <= tolerance {
                    if best == nil || dist < best!.distance {
                        best = (i, .controlOut, dist)
                    }
                }
            }
            // Check anchor (higher priority — overrides handle at same distance)
            let anchorDist = worldPoint.distance(to: bp.point)
            if anchorDist <= tolerance {
                if best == nil || anchorDist <= best!.distance {
                    best = (i, .anchor, anchorDist)
                }
            }
        }
        guard let result = best else { return nil }
        return (result.pointIndex, result.target)
    }

    func startBezierPointDrag(startScreenPoint: CGPoint) -> Bool {
        guard isSingleSelection,
              let id = selectedShapeIds.first,
              let shape = findShape(id: id),
              case .bezier(let bezier) = shape else { return false }

        let worldPoint = transform.screenToWorld(startScreenPoint)
        let tolerance = transform.screenToWorldDistance(8)

        guard let hit = bezierPointHitTest(worldPoint: worldPoint, shape: bezier, tolerance: tolerance) else {
            return false
        }

        draggingBezierPointIndex = hit.pointIndex
        draggingBezierTarget = hit.target
        bezierEditUndoSnapshot = document
        return true
    }

    func dragBezierPoint(to screenPoint: CGPoint, shiftHeld: Bool = false) {
        guard let pointIndex = draggingBezierPointIndex,
              let target = draggingBezierTarget,
              let id = selectedShapeIds.first,
              let (li, si) = findShapeLocation(id: id),
              case .bezier(var bezier) = document.layers[li].shapes[si] else { return }

        let worldPoint = snappedWorldPoint(from: screenPoint)
        let anchor = bezier.points[pointIndex].point

        switch target {
        case .anchor:
            let delta = CGPoint(
                x: worldPoint.x - anchor.x,
                y: worldPoint.y - anchor.y
            )
            bezier.points[pointIndex].point = worldPoint
            bezier.points[pointIndex].controlIn = bezier.points[pointIndex].controlIn + delta
            bezier.points[pointIndex].controlOut = bezier.points[pointIndex].controlOut + delta
        case .controlIn:
            bezier.points[pointIndex].controlIn = worldPoint
            if !shiftHeld {
                // Mirror controlOut symmetrically across anchor
                bezier.points[pointIndex].controlOut = CGPoint(
                    x: 2 * anchor.x - worldPoint.x,
                    y: 2 * anchor.y - worldPoint.y
                )
            }
        case .controlOut:
            bezier.points[pointIndex].controlOut = worldPoint
            if !shiftHeld {
                // Mirror controlIn symmetrically across anchor
                bezier.points[pointIndex].controlIn = CGPoint(
                    x: 2 * anchor.x - worldPoint.x,
                    y: 2 * anchor.y - worldPoint.y
                )
            }
        }

        document.layers[li].shapes[si] = .bezier(bezier)
    }

    func endBezierPointDrag() {
        if let snapshot = bezierEditUndoSnapshot {
            if snapshot != document {
                if let id = selectedShapeIds.first {
                    regenerateStitchLines(forShapeIds: [id])
                }
                registerUndo(actionName: "Edit Bezier Point", oldDocument: snapshot)
            }
        }
        draggingBezierPointIndex = nil
        draggingBezierTarget = nil
        bezierEditUndoSnapshot = nil
        activeSnapCandidate = nil
    }

    // MARK: - Tool Switching

    func selectTool(_ tool: DrawingTool) {
        dragStartWorldPoint = nil
        arcSecondPoint = nil
        dimensionSecondPoint = nil
        bezierPoints = []
        isDraggingBezierHandle = false
        draggingBezierPointIndex = nil
        draggingBezierTarget = nil
        bezierEditUndoSnapshot = nil
        moveUndoSnapshot = nil
        moveDragStartCursorWorld = nil
        moveDragSelectionBBox = nil
        moveAccumulatedDelta = .zero
        drawingPreview = nil
        activeSnapCandidate = nil
        marqueeStart = nil
        marqueeRect = nil
        selectedPageId = nil
        pageMoveUndoSnapshot = nil
        pageDragRawOrigin = nil
        pendingTemplate = nil
        pendingHybridRuns = []
        hybridPickPreview = nil
        currentTool = tool
        if tool != .select {
            selectedShapeIds = []
        }
    }

    // MARK: - Shape Finding

    func findShape(id: UUID) -> AnyShape? {
        for layer in document.layers {
            if let shape = layer.shapes.first(where: { $0.id == id }) {
                return shape
            }
        }
        return nil
    }

    /// Find a shape by id, descending into groups. Stitch lines may reference leaf
    /// shapes nested inside a group (auto-stitch flattens groups before generating),
    /// so resolving sources for regeneration must recurse.
    func findShapeRecursive(id: UUID) -> AnyShape? {
        func search(_ shapes: [AnyShape]) -> AnyShape? {
            for shape in shapes {
                if shape.id == id { return shape }
                if case .group(let group) = shape, let found = search(group.children) { return found }
            }
            return nil
        }
        for layer in document.layers {
            if let shape = search(layer.shapes) { return shape }
        }
        return nil
    }

    func findShapeLocation(id: UUID) -> (layerIndex: Int, shapeIndex: Int)? {
        for (li, layer) in document.layers.enumerated() {
            if let si = layer.shapes.firstIndex(where: { $0.id == id }) {
                return (li, si)
            }
        }
        return nil
    }

    // MARK: - Interactions

    // MARK: - Snapping

    func snappedWorldPoint(from screenPoint: CGPoint) -> CGPoint {
        let worldPoint = transform.screenToWorld(screenPoint)
        let snapTolerance = transform.screenToWorldDistance(8)
        let engine = SnapEngine(tolerance: snapTolerance, settings: document.settings, layers: document.layers, transform: transform)
        let result = engine.snap(worldPoint)
        activeSnapCandidate = result.candidate
        return result.snappedPoint
    }

    /// Snap a world-space point directly. Used by drag-move where the reference is
    /// a point on the shape (not the cursor). Caller can exclude shapes (e.g. the
    /// ones currently being moved) from candidate generation.
    func snapWorldPoint(_ worldPoint: CGPoint, excludedShapeIds: Set<UUID> = []) -> SnapResult {
        let snapTolerance = transform.screenToWorldDistance(8)
        let engine = SnapEngine(tolerance: snapTolerance, settings: document.settings, layers: document.layers, transform: transform, excludedShapeIds: excludedShapeIds)
        return engine.snap(worldPoint)
    }

    func handleClick(at screenPoint: CGPoint, shiftHeld: Bool = false) {
        // Click-to-place: a pending template intercepts the click regardless of tool.
        if let pending = pendingTemplate {
            let placePoint = snappedWorldPoint(from: screenPoint)
            placeTemplate(pending, at: placePoint)
            pendingTemplate = nil
            activeSnapCandidate = nil
            return
        }

        // Hybrid pick: a pending split-point pick intercepts the click regardless of
        // tool. The raw cursor is projected onto the nearest pending run — snapping
        // would pull the point off the path.
        if !pendingHybridRuns.isEmpty {
            commitHybridPick(at: transform.screenToWorld(screenPoint))
            return
        }

        // Select tool must use the raw cursor position so clicks adjacent to grid lines or
        // existing snap targets don't get pulled away from the shape under the cursor.
        let worldPoint: CGPoint = (currentTool == .select)
            ? transform.screenToWorld(screenPoint)
            : snappedWorldPoint(from: screenPoint)
        let tolerance = transform.screenToWorldDistance(5)

        switch currentTool {
        case .select:
            activeSnapCandidate = nil
            let hitId = hitTest(at: worldPoint, tolerance: tolerance)
            if shiftHeld {
                // Shift+click: toggle shape in/out of selection
                if let id = hitId {
                    if selectedShapeIds.contains(id) {
                        selectedShapeIds.remove(id)
                    } else {
                        selectedShapeIds.insert(id)
                    }
                }
            } else {
                // Normal click: select only this shape (deselect others)
                if let id = hitId {
                    selectedShapeIds = [id]
                } else {
                    selectedShapeIds = []
                }
            }

        case .line:
            if let start = dragStartWorldPoint {
                let line = LineShape(start: start, end: worldPoint)
                addShapeWithUndo(.line(line), actionName: "Draw Line")
                dragStartWorldPoint = nil
                drawingPreview = nil
                activeSnapCandidate = nil
            } else {
                dragStartWorldPoint = worldPoint
                drawingPreview = .startPoint(worldPoint)
            }

        case .arc:
            if let start = dragStartWorldPoint, let end = arcSecondPoint {
                // 3rd click: determine arc from 3 points
                if let arc = arcFrom3Points(p1: start, p2: end, p3: worldPoint) {
                    addShapeWithUndo(.arc(arc), actionName: "Draw Arc")
                }
                dragStartWorldPoint = nil
                arcSecondPoint = nil
                drawingPreview = nil
                activeSnapCandidate = nil
            } else if let start = dragStartWorldPoint {
                // 2nd click: set end point
                arcSecondPoint = worldPoint
                drawingPreview = .twoPoints(start, worldPoint)
            } else {
                // 1st click: set start point
                dragStartWorldPoint = worldPoint
                drawingPreview = .startPoint(worldPoint)
            }

        case .bezier:
            let newPoint = BezierPoint(point: worldPoint, controlIn: worldPoint, controlOut: worldPoint)
            bezierPoints.append(newPoint)
            drawingPreview = .bezierPreview(points: bezierPoints, currentPoint: worldPoint)

        case .text:
            let textShape = TextShape(position: worldPoint)
            addShapeWithUndo(.text(textShape), actionName: "Add Text")
            selectedShapeIds = [textShape.id]
            activeSnapCandidate = nil

        case .dimensionLine:
            if let start = dragStartWorldPoint, let second = dimensionSecondPoint {
                // 3rd click: the placement point sets the dimension-line offset
                let dim = DimensionLineShape(start: start, end: second, third: worldPoint, kind: currentDimensionKind)
                addShapeWithUndo(.dimensionLine(dim), actionName: "Draw Dimension")
                selectedShapeIds = [dim.id]
                dragStartWorldPoint = nil
                dimensionSecondPoint = nil
                drawingPreview = nil
                activeSnapCandidate = nil
            } else if let start = dragStartWorldPoint {
                // 2nd click: set the second measured point
                dimensionSecondPoint = worldPoint
                drawingPreview = .twoPoints(start, worldPoint)
            } else {
                // 1st click: set the first measured point
                dragStartWorldPoint = worldPoint
                drawingPreview = .startPoint(worldPoint)
            }

        case .offset:
            // Click on a shape to offset it
            if let hitId = hitTest(at: worldPoint, tolerance: tolerance) {
                selectedShapeIds = [hitId]
                offsetSelectedShape(distance: 3.0)
            }

        case .trim:
            // Click on a line to trim at the clicked point
            if let hitId = hitTest(at: worldPoint, tolerance: tolerance) {
                selectedShapeIds = [hitId]
                trimSelectedShape(clickPoint: worldPoint)
            }

        case .bevel:
            // Click a corner to round it: a line corner, or a single rectangle corner.
            if let hitId = hitTest(at: worldPoint, tolerance: tolerance) {
                selectedShapeIds = [hitId]
                bevelClickedCorner(shapeId: hitId, near: worldPoint, radius: bevelRadius)
            }

        case .page:
            activeSnapCandidate = nil
            if !selectPage(at: worldPoint) {
                addPage(at: worldPoint)
            }

        default:
            break
        }
    }

    func handleMouseMove(screenPoint: CGPoint) {
        let worldPoint = snappedWorldPoint(from: screenPoint)
        cursorWorldPosition = worldPoint

        // While placing a template, the snapped cursor drives the ghost preview.
        if pendingTemplate != nil { return }

        // While picking the hybrid split point, the raw cursor drives the ghost holes.
        if !pendingHybridRuns.isEmpty {
            updateHybridPickPreview(at: transform.screenToWorld(screenPoint))
            return
        }

        switch currentTool {
        case .line:
            if let start = dragStartWorldPoint {
                drawingPreview = .lineFromClick(start: start, end: worldPoint)
            }
        case .arc:
            if let start = dragStartWorldPoint, let end = arcSecondPoint {
                // 3rd point hover: show arc preview
                if let arc = arcFrom3Points(p1: start, p2: end, p3: worldPoint) {
                    drawingPreview = .arcPreview(center: arc.center, radius: arc.radius, startAngle: arc.startAngle, endAngle: arc.endAngle, clockwise: arc.clockwise)
                }
            } else if let start = dragStartWorldPoint {
                // 2nd point hover: show line from start to cursor
                drawingPreview = .lineFromClick(start: start, end: worldPoint)
            }
        case .bezier:
            if !bezierPoints.isEmpty {
                drawingPreview = .bezierPreview(points: bezierPoints, currentPoint: worldPoint)
            }
        case .dimensionLine:
            if let start = dragStartWorldPoint, let second = dimensionSecondPoint {
                // 3rd point hover: show the dimension preview following the cursor
                let dim = DimensionLineShape(start: start, end: second, third: worldPoint, kind: currentDimensionKind)
                drawingPreview = .dimensionPreview(dim)
            } else if let start = dragStartWorldPoint {
                // 2nd point hover: show line from start to cursor
                drawingPreview = .lineFromClick(start: start, end: worldPoint)
            }
        default:
            break
        }
    }

    /// Constrain `endPoint` so the rectangle from `start` to `endPoint` is a square.
    private func constrainToSquare(start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(
            x: start.x + (dx >= 0 ? side : -side),
            y: start.y + (dy >= 0 ? side : -side)
        )
    }

    func handleDrag(startLocation: CGPoint, currentLocation: CGPoint, phase: DragPhase, shiftHeld: Bool = false) {
        let worldPoint = snappedWorldPoint(from: currentLocation)

        switch currentTool {
        case .rectangle:
            if phase == .changed {
                if dragStartWorldPoint == nil {
                    // Use the drag's actual start position, snapped
                    dragStartWorldPoint = snappedWorldPoint(from: startLocation)
                }
                if let start = dragStartWorldPoint {
                    let end = shiftHeld ? constrainToSquare(start: start, end: worldPoint) : worldPoint
                    let origin = CGPoint(x: min(start.x, end.x), y: min(start.y, end.y))
                    let size = CGSize(width: abs(end.x - start.x), height: abs(end.y - start.y))
                    drawingPreview = .rectangle(origin: origin, size: size)
                }
            } else if phase == .ended, let start = dragStartWorldPoint {
                let end = shiftHeld ? constrainToSquare(start: start, end: worldPoint) : worldPoint
                let rect = RectangleShape(from: start, to: end)
                addShapeWithUndo(.rectangle(rect), actionName: "Draw Rectangle")
                dragStartWorldPoint = nil
                drawingPreview = nil
                activeSnapCandidate = nil
            }

        case .ellipse:
            if phase == .changed {
                if dragStartWorldPoint == nil {
                    dragStartWorldPoint = snappedWorldPoint(from: startLocation)
                }
                if let start = dragStartWorldPoint {
                    let end = shiftHeld ? constrainToSquare(start: start, end: worldPoint) : worldPoint
                    let center = start.midpoint(to: end)
                    let rx = abs(end.x - start.x) / 2
                    let ry = abs(end.y - start.y) / 2
                    drawingPreview = .ellipsePreview(center: center, radiusX: rx, radiusY: ry)
                }
            } else if phase == .ended, let start = dragStartWorldPoint {
                let end = shiftHeld ? constrainToSquare(start: start, end: worldPoint) : worldPoint
                let center = start.midpoint(to: end)
                let rx = abs(end.x - start.x) / 2
                let ry = abs(end.y - start.y) / 2
                if rx > 0.5 && ry > 0.5 {
                    let ellipse = EllipseShape(center: center, radiusX: rx, radiusY: ry)
                    addShapeWithUndo(.ellipse(ellipse), actionName: "Draw Ellipse")
                }
                dragStartWorldPoint = nil
                drawingPreview = nil
                activeSnapCandidate = nil
            }

        case .line:
            if phase == .changed {
                if dragStartWorldPoint == nil {
                    dragStartWorldPoint = snappedWorldPoint(from: startLocation)
                }
                if let start = dragStartWorldPoint {
                    drawingPreview = .lineFromDrag(start: start, end: worldPoint)
                }
            } else if phase == .ended, let start = dragStartWorldPoint {
                let line = LineShape(start: start, end: worldPoint)
                addShapeWithUndo(.line(line), actionName: "Draw Line")
                dragStartWorldPoint = nil
                drawingPreview = nil
                activeSnapCandidate = nil
            }

        case .bezier:
            if phase == .changed {
                let startWorld = snappedWorldPoint(from: startLocation)
                if !isDraggingBezierHandle {
                    let newPoint = BezierPoint(point: startWorld, controlIn: startWorld, controlOut: startWorld)
                    bezierPoints.append(newPoint)
                    isDraggingBezierHandle = true
                }
                if var lastPoint = bezierPoints.last {
                    let anchor = lastPoint.point
                    lastPoint.controlOut = worldPoint
                    lastPoint.controlIn = CGPoint(
                        x: 2 * anchor.x - worldPoint.x,
                        y: 2 * anchor.y - worldPoint.y
                    )
                    bezierPoints[bezierPoints.count - 1] = lastPoint
                }
                drawingPreview = .bezierPreview(points: bezierPoints, currentPoint: worldPoint)
            } else if phase == .ended {
                isDraggingBezierHandle = false
                drawingPreview = .bezierPreview(points: bezierPoints, currentPoint: worldPoint)
            }

        default:
            break
        }
    }

    /// Translate the current selection. Pass `live: true` for per-frame drag updates so
    /// partially-moved stitch runs are parked rather than resolved every frame; the weld
    /// decision is then settled once in `commitMoveWithUndo`. One-shot moves keep the
    /// default (`live: false`) and resolve immediately. (#33)
    func moveSelectedShapes(by worldDelta: CGPoint, live: Bool = false) {
        var movedIds: Set<UUID> = []
        for id in selectedShapeIds {
            if let (li, si) = findShapeLocation(id: id) {
                movedIds.formUnion(collectShapeIds(in: document.layers[li].shapes[si]))
                document.layers[li].shapes[si].translate(by: worldDelta)
            }
        }
        translateStitchHoles(forShapeIds: movedIds, by: worldDelta, live: live)
    }

    func deleteSelectedShapes() {
        guard hasSelection else { return }
        let old = document
        // Expand to descendant ids so stitch lines bound to group children are also removed.
        var idsToDelete: Set<UUID> = []
        for id in selectedShapeIds {
            if let shape = findShape(id: id) {
                idsToDelete.formUnion(collectShapeIds(in: shape))
            } else {
                idsToDelete.insert(id)
            }
        }
        for (li, layer) in document.layers.enumerated() {
            document.layers[li].shapes = layer.shapes.filter { !idsToDelete.contains($0.id) }
            document.layers[li].stitchLines = layer.stitchLines.filter { !$0.sourceShapeIds.contains(where: idsToDelete.contains) }
        }
        selectedShapeIds = []
        // The deleted shapes may back a pending hybrid pick; a later click would then
        // commit a stitch line whose sources no longer exist. Drop the pick wholesale.
        pendingHybridRuns = []
        hybridPickPreview = nil
        registerUndo(actionName: "Delete Shape", oldDocument: old)
    }

    func cancelDrawing() {
        // Cancel a pending template placement first (Escape).
        if pendingTemplate != nil {
            pendingTemplate = nil
            activeSnapCandidate = nil
            return
        }
        // Cancel a pending hybrid split-point pick (Escape). Runs already committed
        // by earlier clicks keep their stitch lines; only the rest are dropped.
        if !pendingHybridRuns.isEmpty {
            pendingHybridRuns = []
            hybridPickPreview = nil
            return
        }
        // If bezier has 2+ points, commit what we have before cancelling
        if currentTool == .bezier && bezierPoints.count >= 2 {
            commitBezier()
            return
        }
        dragStartWorldPoint = nil
        arcSecondPoint = nil
        bezierPoints = []
        isDraggingBezierHandle = false
        drawingPreview = nil
        activeSnapCandidate = nil
        marqueeStart = nil
        marqueeRect = nil
        moveDragStartCursorWorld = nil
        moveDragSelectionBBox = nil
        moveAccumulatedDelta = .zero
    }

    /// Commit the current bezier path (called by Enter/Escape/double-click)
    func commitBezier() {
        guard bezierPoints.count >= 2 else {
            bezierPoints = []
            drawingPreview = nil
            return
        }
        let shape = BezierShape(points: bezierPoints)
        addShapeWithUndo(.bezier(shape), actionName: "Draw Bezier")
        bezierPoints = []
        isDraggingBezierHandle = false
        drawingPreview = nil
        activeSnapCandidate = nil
    }

    // MARK: - Arc from 3 Points

    /// Calculate a circular arc from p1 to p2, passing through p3.
    /// The 3rd point (p3) determines which side the arc bulges towards.
    private func arcFrom3Points(p1: CGPoint, p2: CGPoint, p3: CGPoint) -> ArcShape? {
        // Find circumcenter of triangle p1-p2-p3
        let ax = p1.x, ay = p1.y
        let bx = p2.x, by = p2.y
        let cx = p3.x, cy = p3.y

        let d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
        guard abs(d) > 1e-10 else { return nil } // collinear

        let ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
        let uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d

        let center = CGPoint(x: ux, y: uy)
        let radius = center.distance(to: p1)

        let angle1 = atan2(p1.y - center.y, p1.x - center.x)
        let angle2 = atan2(p2.y - center.y, p2.x - center.x)
        let angle3 = atan2(p3.y - center.y, p3.x - center.x)

        // Determine if going counterclockwise from angle1 passes through angle3 before angle2.
        // SwiftUI's addArc with clockwise:false goes counterclockwise in standard math coords,
        // but in screen coords (y-down) it appears clockwise visually. We need to pick the
        // direction that includes p3.
        let ccw = isAngleBetweenCCW(target: angle3, from: angle1, to: angle2)

        // If p3 is on the CCW path from p1→p2, use clockwise:false (CCW in math = CW on screen)
        // If p3 is NOT on CCW path, use clockwise:true
        let clockwise = !ccw

        return ArcShape(center: center, radius: radius, startAngle: angle1, endAngle: angle2, clockwise: clockwise)
    }

    /// Check if `target` angle lies on the counter-clockwise arc from `from` to `to`.
    private func isAngleBetweenCCW(target: CGFloat, from: CGFloat, to: CGFloat) -> Bool {
        // Normalize all angles to [0, 2π)
        func norm(_ a: CGFloat) -> CGFloat {
            var r = a.truncatingRemainder(dividingBy: 2 * .pi)
            if r < 0 { r += 2 * .pi }
            return r
        }
        let s = norm(from)
        let e = norm(to)
        let t = norm(target)

        if s <= e {
            return t >= s && t <= e
        } else {
            // Arc wraps around 0
            return t >= s || t <= e
        }
    }

    // MARK: - Editing Tools

    /// Offset the selected shape by a distance (mm). Positive = outward, negative = inward.
    func offsetSelectedShape(distance: CGFloat) {
        guard let id = selectedShapeIds.first,
              let shape = findShape(id: id) else { return }

        let old = document
        var newShape: AnyShape?

        switch shape {
        case .line(let line):
            newShape = .line(OffsetTool.offsetLine(line, distance: distance))
        case .rectangle(let rect):
            newShape = .rectangle(OffsetTool.offsetRectangle(rect, distance: distance))
        case .ellipse(let ellipse):
            newShape = .ellipse(OffsetTool.offsetEllipse(ellipse, distance: distance))
        case .arc(let arc):
            newShape = OffsetTool.offsetArc(arc, distance: distance).map { .arc($0) }
        case .bezier(let bezier):
            newShape = .bezier(OffsetTool.offsetBezier(bezier, distance: distance))
        default:
            break
        }

        if let newShape {
            activeLayer.shapes.append(newShape)
            registerUndo(actionName: "Offset", oldDocument: old)
        }
    }

    /// Trim the selected shape at intersections with other shapes, removing the clicked segment.
    func trimSelectedShape(clickPoint: CGPoint) {
        guard let id = selectedShapeIds.first,
              let (li, si) = findShapeLocation(id: id) else { return }

        let shape = document.layers[li].shapes[si]
        let others = document.layers[li].shapes
        guard let result = TrimTool.trim(shape: shape, against: others, clickPoint: clickPoint) else { return }

        let old = document
        let removedId = shape.id
        document.layers[li].shapes.remove(at: si)
        document.layers[li].shapes.insert(contentsOf: result.replacements, at: si)
        // Source shape no longer exists → helper drops its stitch lines.
        regenerateStitchLines(forShapeIds: [removedId])
        selectedShapeIds = []
        registerUndo(actionName: "Trim", oldDocument: old)
    }

    /// Trim selected shape from toolbar (uses midpoint as click point).
    func trimSelectedShapeAtCenter() {
        guard let id = selectedShapeIds.first,
              let shape = findShape(id: id) else { return }
        trimSelectedShape(clickPoint: shape.boundingBox.center)
    }

    /// Bevel the single corner nearest the clicked point on the hit shape.
    /// Lines round the adjacent corner closest to the click; a rectangle explodes
    /// into 4 edges and only the clicked corner is filleted (so individual corners
    /// can be rounded — e.g. just the bottom two).
    func bevelClickedCorner(shapeId: UUID, near point: CGPoint, radius: CGFloat) {
        guard let (li, si) = findShapeLocation(id: shapeId) else { return }
        switch document.layers[li].shapes[si] {
        case .rectangle(let rect):
            bevelRectangleCorner(rect, layer: li, index: si, near: point, radius: radius)
        case .line:
            bevelLineCorner(lineId: shapeId, layer: li, near: point, radius: radius)
        default:
            break
        }
    }

    /// Explode a rectangle into 4 line edges and fillet only the corner nearest
    /// the click. The other three corners stay sharp (as connected line edges),
    /// so further clicks can round them too. Any uniform `cornerRadius` is dropped.
    private func bevelRectangleCorner(_ rect: RectangleShape, layer li: Int, index si: Int, near point: CGPoint, radius: CGFloat) {
        let c = rect.rotatedCorners  // [TL, TR, BR, BL]
        var edges = [
            LineShape(start: c[0], end: c[1], stroke: rect.stroke),  // 0 top
            LineShape(start: c[1], end: c[2], stroke: rect.stroke),  // 1 right
            LineShape(start: c[2], end: c[3], stroke: rect.stroke),  // 2 bottom
            LineShape(start: c[3], end: c[0], stroke: rect.stroke),  // 3 left
        ]
        // Nearest corner; corner i is shared by edge (i+3)%4 (incoming) and edge i (outgoing).
        let ci = (0..<4).min(by: { c[$0].distance(to: point) < c[$1].distance(to: point) }) ?? 0
        let inIdx = (ci + 3) % 4
        let outIdx = ci
        guard let result = BevelTool.bevel(line1: edges[inIdx], line2: edges[outIdx], radius: radius) else { return }

        let old = document
        edges[inIdx] = LineShape(id: edges[inIdx].id, start: result.line1.startPoint, end: result.line1.endPoint, stroke: result.line1.stroke)
        edges[outIdx] = LineShape(id: edges[outIdx].id, start: result.line2.startPoint, end: result.line2.endPoint, stroke: result.line2.stroke)

        // Drop any edge the fillet fully consumed (zero length, when radius == edge).
        var replacements: [AnyShape] = edges.filter { $0.length > 1e-6 }.map { .line($0) }
        replacements.append(.arc(result.arc))
        document.layers[li].shapes.remove(at: si)
        document.layers[li].shapes.insert(contentsOf: replacements, at: si)
        // The rectangle is replaced by its filleted edges + arc; re-point stitch lines
        // that tracked it so they re-weld over the new outline instead of being dropped.
        let newIds = replacements.map { $0.id }
        remapStitchLineSources(containingAll: [rect.id], removing: [rect.id], adding: newIds)
        regenerateStitchLines(forShapeIds: Set(newIds))
        selectedShapeIds = []
        registerUndo(actionName: "Bevel Corner", oldDocument: old)
    }

    /// Fillet the corner where the clicked line meets an adjacent line, choosing
    /// the shared vertex nearest the click when the line has corners at both ends.
    private func bevelLineCorner(lineId: UUID, layer li: Int, near point: CGPoint, radius: CGFloat) {
        guard let si = document.layers[li].shapes.firstIndex(where: { $0.id == lineId }),
              case .line(let line1) = document.layers[li].shapes[si] else { return }

        var best: (index: Int, line: LineShape, vertexDist: CGFloat)?
        for (si2, shape) in document.layers[li].shapes.enumerated() {
            guard si2 != si, case .line(let line2) = shape,
                  let vertex = sharedEndpoint(line1, line2, tolerance: 0.5) else { continue }
            let d = vertex.distance(to: point)
            if best == nil || d < best!.vertexDist { best = (si2, line2, d) }
        }
        guard let pick = best,
              let result = BevelTool.bevel(line1: line1, line2: pick.line, radius: radius) else { return }

        let old = document
        // Preserve original ids so stitch lines keep tracking each shortened line.
        let preservedLine1 = LineShape(id: line1.id, start: result.line1.startPoint, end: result.line1.endPoint, stroke: result.line1.stroke)
        let preservedLine2 = LineShape(id: pick.line.id, start: result.line2.startPoint, end: result.line2.endPoint, stroke: result.line2.stroke)
        document.layers[li].shapes[si] = .line(preservedLine1)
        document.layers[li].shapes[pick.index] = .line(preservedLine2)
        document.layers[li].shapes.append(.arc(result.arc))
        // Drop any edge the fillet fully consumed (zero length, when radius == edge),
        // and drop its id from the selection so the panel/overlay don't dangle on it.
        var dropIndices: [Int] = []
        var removedIds: Set<UUID> = []
        if preservedLine1.length < 1e-6 { dropIndices.append(si); selectedShapeIds.remove(line1.id); removedIds.insert(line1.id) }
        if preservedLine2.length < 1e-6 { dropIndices.append(pick.index); selectedShapeIds.remove(pick.line.id); removedIds.insert(pick.line.id) }
        for idx in dropIndices.sorted(by: >) { document.layers[li].shapes.remove(at: idx) }
        // Weave the new fillet arc into stitch lines that follow these edges so a welded
        // outline reconnects through the fillet instead of splitting and being dropped.
        remapStitchLineSources(containingAll: [line1.id, pick.line.id], removing: removedIds, adding: [result.arc.id])
        regenerateStitchLines(forShapeIds: [line1.id, pick.line.id, result.arc.id])
        registerUndo(actionName: "Bevel Corner", oldDocument: old)
    }

    /// The point where two lines meet within tolerance, or nil if they don't share an endpoint.
    private func sharedEndpoint(_ a: LineShape, _ b: LineShape, tolerance: CGFloat) -> CGPoint? {
        let pairs = [(a.endPoint, b.startPoint), (a.endPoint, b.endPoint),
                     (a.startPoint, b.startPoint), (a.startPoint, b.endPoint)]
        for (p, q) in pairs where p.distance(to: q) < tolerance { return p }
        return nil
    }

    // MARK: - Bulk Bevel (range selection)

    /// Round every detected corner across the current selection in one pass.
    /// Rectangles get a non-destructive `cornerRadius`; selected line corners and
    /// straight bézier corners are filleted. Returns the number of corners rounded.
    @discardableResult
    func bevelSelectedCorners(radius: CGFloat) -> Int {
        guard radius > 0, hasSelection else { return 0 }

        let old = document
        var totalCorners = 0
        var affectedShapeIds = Set<UUID>()

        for li in document.layers.indices {
            guard document.layers[li].shapes.contains(where: { selectedShapeIds.contains($0.id) }) else { continue }

            // 1. Rectangles → set cornerRadius (non-destructive, clamped to fit).
            for si in document.layers[li].shapes.indices {
                guard selectedShapeIds.contains(document.layers[li].shapes[si].id),
                      case .rectangle(var rect) = document.layers[li].shapes[si] else { continue }
                let maxR = min(rect.size.width, rect.size.height) / 2
                let r = min(radius, maxR)
                guard r > 0 else { continue }
                rect.cornerRadius = r
                document.layers[li].shapes[si] = .rectangle(rect)
                totalCorners += 4
                affectedShapeIds.insert(rect.id)
            }

            // 2. Béziers → fillet straight-segment corner anchors in place.
            for si in document.layers[li].shapes.indices {
                guard selectedShapeIds.contains(document.layers[li].shapes[si].id),
                      case .bezier(let bezier) = document.layers[li].shapes[si] else { continue }
                let (newBezier, count) = Self.beveledBezier(bezier, radius: radius)
                guard count > 0 else { continue }
                document.layers[li].shapes[si] = .bezier(newBezier)
                totalCorners += count
                affectedShapeIds.insert(bezier.id)
            }

            // 3. Lines → fillet shared-endpoint corners among the selected lines.
            totalCorners += bevelSelectedLines(inLayer: li, radius: radius, affectedShapeIds: &affectedShapeIds)
        }

        guard totalCorners > 0 else { return 0 }
        regenerateStitchLines(forShapeIds: affectedShapeIds)
        registerUndo(actionName: "Bevel", oldDocument: old)
        return totalCorners
    }

    /// Non-mutating estimate of how many corners `bevelSelectedCorners` would round,
    /// used to preview the count in the Bevel sheet.
    func bevelableCornerCount(radius: CGFloat) -> Int {
        guard radius > 0, hasSelection else { return 0 }
        var total = 0
        for layer in document.layers {
            let selected = layer.shapes.filter { selectedShapeIds.contains($0.id) }
            for shape in selected {
                switch shape {
                case .rectangle(let rect):
                    if min(rect.size.width, rect.size.height) / 2 > 0 { total += 4 }
                case .bezier(let bezier):
                    total += Self.beveledBezier(bezier, radius: radius).1
                default:
                    break
                }
            }
            total += countLineCorners(selectedLines: selected.compactMap {
                if case .line(let l) = $0 { return l } else { return nil }
            }, radius: radius)
        }
        return total
    }

    /// Fillet every corner shared by exactly two of the selected lines in a layer.
    /// Returns the number of corners rounded. Lines are shortened in place (ids
    /// preserved so stitch lines keep tracking them); a fillet arc is appended per corner.
    private func bevelSelectedLines(inLayer li: Int, radius: CGFloat, affectedShapeIds: inout Set<UUID>) -> Int {
        // Working geometry of the selected lines, keyed by shape index.
        var working: [Int: LineShape] = [:]
        for si in document.layers[li].shapes.indices {
            if case .line(let l) = document.layers[li].shapes[si], selectedShapeIds.contains(l.id) {
                working[si] = l
            }
        }
        guard working.count >= 2 else { return 0 }

        let corners = Self.detectLineCorners(working)
        guard !corners.isEmpty else { return 0 }

        var arcs: [ArcShape] = []
        var count = 0
        for corner in corners {
            var lineA = working[corner.siA]!
            var lineB = working[corner.siB]!
            let vertex = corner.isStartA ? lineA.startPoint : lineA.endPoint
            let farA = corner.isStartA ? lineA.endPoint : lineA.startPoint
            let farB = corner.isStartB ? lineB.endPoint : lineB.startPoint

            guard let fillet = BevelTool.filletCorner(prev: farA, corner: vertex, next: farB, radius: radius) else { continue }

            if corner.isStartA { lineA.startPoint = fillet.tangentPrev } else { lineA.endPoint = fillet.tangentPrev }
            if corner.isStartB { lineB.startPoint = fillet.tangentNext } else { lineB.endPoint = fillet.tangentNext }
            working[corner.siA] = lineA
            working[corner.siB] = lineB

            arcs.append(ArcShape(center: fillet.center, radius: fillet.radius,
                                 startAngle: fillet.startAngle, endAngle: fillet.endAngle,
                                 clockwise: fillet.clockwise, stroke: lineA.stroke))
            count += 1
        }
        guard count > 0 else { return 0 }

        for (si, line) in working {
            document.layers[li].shapes[si] = .line(line)
            affectedShapeIds.insert(line.id)
        }
        for arc in arcs { document.layers[li].shapes.append(.arc(arc)) }
        // Drop any edge a fillet fully consumed (zero length, when radius == edge).
        for idx in working.filter({ $0.value.length < 1e-6 }).keys.sorted(by: >) {
            document.layers[li].shapes.remove(at: idx)
        }
        return count
    }

    /// A corner shared by two distinct selected lines.
    private struct LineCorner {
        let siA: Int; let isStartA: Bool
        let siB: Int; let isStartB: Bool
    }

    /// Cluster the endpoints of the working lines and return vertices shared by
    /// exactly two distinct lines. Vertices where 3+ lines meet are ambiguous and skipped.
    private static func detectLineCorners(_ working: [Int: LineShape], tolerance: CGFloat = 0.5) -> [LineCorner] {
        struct EndRef { let si: Int; let isStart: Bool; let point: CGPoint }
        var ends: [EndRef] = []
        for (si, l) in working {
            ends.append(EndRef(si: si, isStart: true, point: l.startPoint))
            ends.append(EndRef(si: si, isStart: false, point: l.endPoint))
        }
        // Deterministic order: Dictionary iteration is per-run randomized, which would
        // otherwise make *which* corners get beveled (when some are skipped) vary by run.
        ends.sort { ($0.si, $0.isStart ? 0 : 1) < ($1.si, $1.isStart ? 0 : 1) }

        // Greedy proximity clustering — selections are small, so O(n²) is fine.
        var clusters: [[EndRef]] = []
        for e in ends {
            if let idx = clusters.firstIndex(where: { $0[0].point.distance(to: e.point) <= tolerance }) {
                clusters[idx].append(e)
            } else {
                clusters.append([e])
            }
        }

        var corners: [LineCorner] = []
        for cluster in clusters where cluster.count == 2 {
            let (a, b) = cluster[0].si <= cluster[1].si ? (cluster[0], cluster[1]) : (cluster[1], cluster[0])
            guard a.si != b.si else { continue }
            corners.append(LineCorner(siA: a.si, isStartA: a.isStart, siB: b.si, isStartB: b.isStart))
        }
        corners.sort { ($0.siA, $0.siB) < ($1.siA, $1.siB) }
        return corners
    }

    /// Count line corners for the preview. Mirrors `bevelSelectedLines` exactly —
    /// shortening each leg as it goes — so the previewed count matches what Apply does
    /// (a later corner sharing an already-shortened leg may no longer fit).
    private func countLineCorners(selectedLines lines: [LineShape], radius: CGFloat) -> Int {
        guard lines.count >= 2 else { return 0 }
        var working: [Int: LineShape] = [:]
        for (i, l) in lines.enumerated() { working[i] = l }
        var count = 0
        for corner in Self.detectLineCorners(working) {
            var lineA = working[corner.siA]!
            var lineB = working[corner.siB]!
            let vertex = corner.isStartA ? lineA.startPoint : lineA.endPoint
            let farA = corner.isStartA ? lineA.endPoint : lineA.startPoint
            let farB = corner.isStartB ? lineB.endPoint : lineB.startPoint
            guard let fillet = BevelTool.filletCorner(prev: farA, corner: vertex, next: farB, radius: radius) else { continue }
            if corner.isStartA { lineA.startPoint = fillet.tangentPrev } else { lineA.endPoint = fillet.tangentPrev }
            if corner.isStartB { lineB.startPoint = fillet.tangentNext } else { lineB.endPoint = fillet.tangentNext }
            working[corner.siA] = lineA
            working[corner.siB] = lineB
            count += 1
        }
        return count
    }

    /// Fillet the straight-segment corner anchors of a bézier in place, keeping it a
    /// single connected path. Curved-segment anchors are left untouched (limitation).
    /// Returns the updated shape and the number of corners rounded.
    ///
    /// Adjacent corners that share a straight segment are accepted greedily so their
    /// tangent points never overrun each other on that segment — overrunning would
    /// reverse the segment direction and self-intersect the path.
    private static func beveledBezier(_ bezier: BezierShape, radius: CGFloat) -> (BezierShape, Int) {
        let pts = bezier.points
        let n = pts.count
        guard n >= 3 else { return (bezier, 0) }

        func segLen(_ k: Int) -> CGFloat { pts[k].point.distance(to: pts[(k + 1) % n].point) }
        // Interior anchors for an open path; every anchor for a closed loop.
        let indices: [Int] = bezier.isClosed ? Array(0..<n) : Array(1..<(n - 1))

        // Candidate fillet per corner, measured against the full original legs.
        var fillets: [Int: BevelTool.CornerFillet] = [:]
        var tangentDist: [Int: CGFloat] = [:]
        for i in indices {
            let prevP = pts[(i - 1 + n) % n], curP = pts[i], nextP = pts[(i + 1) % n]
            guard isStraightSegment(from: prevP, to: curP),
                  isStraightSegment(from: curP, to: nextP),
                  let f = BevelTool.filletCorner(prev: prevP.point, corner: curP.point, next: nextP.point, radius: radius)
            else { continue }
            fillets[i] = f
            tangentDist[i] = curP.point.distance(to: f.tangentPrev)
        }
        guard !fillets.isEmpty else { return (bezier, 0) }

        // Greedily accept corners so two fillets never overrun a shared segment.
        var consumed: [Int: CGFloat] = [:]
        var accepted = Set<Int>()
        for i in indices {
            guard let td = tangentDist[i] else { continue }
            let inSeg = (i - 1 + n) % n
            let outSeg = i % n
            guard (consumed[inSeg] ?? 0) + td <= segLen(inSeg) + 1e-6,
                  (consumed[outSeg] ?? 0) + td <= segLen(outSeg) + 1e-6 else { continue }
            accepted.insert(i)
            consumed[inSeg, default: 0] += td
            consumed[outSeg, default: 0] += td
        }
        guard !accepted.isEmpty else { return (bezier, 0) }

        // Replace each accepted corner anchor with the fillet arc (≤90° cubic chain).
        var newPoints: [BezierPoint] = []
        for i in 0..<n {
            guard accepted.contains(i), let f = fillets[i] else { newPoints.append(pts[i]); continue }
            newPoints.append(contentsOf: BevelTool.arcBezierAnchors(from: f.tangentPrev, to: f.tangentNext,
                                                                    center: f.center, radius: f.radius))
        }
        var result = bezier
        result.points = newPoints
        return (result, accepted.count)
    }

    /// A bézier segment is "straight" when both of its control handles lie on the
    /// chord between the two anchors (within tolerance).
    private static func isStraightSegment(from a: BezierPoint, to b: BezierPoint, tolerance: CGFloat = 0.05) -> Bool {
        let chord = a.point.distance(to: b.point)
        guard chord > 1e-6 else { return false }
        return distancePointToLine(a.controlOut, a.point, b.point) <= tolerance
            && distancePointToLine(b.controlIn, a.point, b.point) <= tolerance
    }

    /// Perpendicular distance from `p` to the infinite line through `a` and `b`.
    private static func distancePointToLine(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 1e-9 else { return p.distance(to: a) }
        return abs((p.x - a.x) * dy - (p.y - a.y) * dx) / len
    }

    // MARK: - Group / Ungroup

    /// Group the currently selected shapes into a single group.
    func groupSelectedShapes() {
        guard selectedShapeIds.count >= 2 else { return }
        let old = document

        var groupChildren: [AnyShape] = []
        var remainingShapes: [AnyShape] = []
        var insertionIndex: Int?

        for (i, shape) in activeLayer.shapes.enumerated() {
            if selectedShapeIds.contains(shape.id) {
                groupChildren.append(shape)
                if insertionIndex == nil { insertionIndex = i }
            } else {
                remainingShapes.append(shape)
            }
        }

        guard groupChildren.count >= 2 else { return }

        let group = GroupShape(children: groupChildren)
        let idx = min(insertionIndex ?? 0, remainingShapes.count)
        remainingShapes.insert(.group(group), at: idx)
        activeLayer.shapes = remainingShapes

        selectedShapeIds = [group.id]
        registerUndo(actionName: "Group", oldDocument: old)
    }

    /// Ungroup selected groups, restoring their children to the layer.
    func ungroupSelectedShapes() {
        let old = document
        var changed = false
        var childIds = Set<UUID>()

        // Process in reverse to preserve indices
        for id in selectedShapeIds {
            guard let (li, si) = findShapeLocation(id: id),
                  case .group(let group) = document.layers[li].shapes[si] else { continue }

            for child in group.children { childIds.insert(child.id) }
            document.layers[li].shapes.remove(at: si)
            document.layers[li].shapes.insert(contentsOf: group.children, at: si)
            changed = true
        }

        guard changed else { return }
        selectedShapeIds = childIds
        registerUndo(actionName: "Ungroup", oldDocument: old)
    }

    /// Whether any of the selected shapes is a group.
    var hasSelectedGroup: Bool {
        selectedShapes.contains { if case .group = $0 { return true } else { return false } }
    }

    // MARK: - Select All

    func selectAll() {
        let layer = activeLayer
        selectedShapeIds = Set(layer.shapes.map(\.id))
    }

    // MARK: - Marquee Selection

    func beginMarquee(at screenPoint: CGPoint) {
        marqueeStart = screenPoint
        marqueeRect = CGRect(origin: screenPoint, size: .zero)
    }

    func updateMarquee(to screenPoint: CGPoint, shiftHeld: Bool) {
        guard let start = marqueeStart else { return }
        let rect = CGRect(from: start, to: screenPoint)
        marqueeRect = rect

        // Convert marquee rect from screen to world coordinates
        let worldOrigin = transform.screenToWorld(rect.origin)
        let worldEnd = transform.screenToWorld(CGPoint(x: rect.maxX, y: rect.maxY))
        let worldRect = CGRect(from: worldOrigin, to: worldEnd)

        // Find all shapes whose bounding box intersects the marquee
        var newSelection = shiftHeld ? selectedShapeIds : Set<UUID>()
        for layer in document.layers where layer.isVisible {
            for shape in layer.shapes {
                if shape.boundingBox.intersects(worldRect) {
                    newSelection.insert(shape.id)
                }
            }
        }
        selectedShapeIds = newSelection
    }

    func endMarquee() {
        marqueeStart = nil
        marqueeRect = nil
    }

    // MARK: - Hit Testing

    func hitTestPublic(at worldPoint: CGPoint, tolerance: CGFloat) -> UUID? {
        hitTest(at: worldPoint, tolerance: tolerance)
    }

    private func hitTest(at worldPoint: CGPoint, tolerance: CGFloat) -> UUID? {
        for layer in document.layers.reversed() where layer.isVisible {
            for shape in layer.shapes.reversed() {
                if shape.hitTest(point: worldPoint, tolerance: tolerance) {
                    return shape.id
                }
            }
        }
        return nil
    }

    // MARK: - Zoom

    func zoomIn(center: CGPoint? = nil) {
        let c = center ?? CGPoint(x: 600, y: 400)
        transform.zoom(by: 1.2, center: c)
    }

    func zoomOut(center: CGPoint? = nil) {
        let c = center ?? CGPoint(x: 600, y: 400)
        transform.zoom(by: 1 / 1.2, center: c)
    }

    func zoomToFit() {
        transform.offset = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        transform.scale = 3.0
    }

    func setZoomPercentage(_ percentage: CGFloat) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let worldCenter = transform.screenToWorld(center)
        transform.scale = max(0.5, min(50, percentage / 100.0 * 3.0))
        transform.offset.x = center.x - worldCenter.x * transform.scale
        transform.offset.y = center.y - worldCenter.y * transform.scale
    }

    // MARK: - Auto Stitch

    /// Whether the stitch mode choice changes the result for the current selection.
    /// Corner-anchored paths (rectangles, welded outlines) are always evenly spaced
    /// per span regardless of mode, so the picker only matters when at least one
    /// resulting run has no corners: on open smooth runs Fixed/Variable/Even Count
    /// all differ, and on closed smooth runs (circles) Even Count still differs from
    /// the pitch-derived spacing (#23b). With no stitchable selection the picker
    /// stays enabled as a plain default setting.
    var stitchModeAffectsSelection: Bool {
        let leaves = selectedShapeIds
            .compactMap { findShape(id: $0) }
            .flatMap { leafShapes(of: $0) }
        let paths = StitchPathBuilder.build(from: leaves)
        guard !paths.isEmpty else { return true }
        return paths.contains { $0.walker.cornerDistances.isEmpty }
    }

    func autoStitchSelectedShape() {
        guard let iron = activePrickingIron else { return }

        // Expand the selection into stitchable leaf shapes (recursing into groups),
        // then weld connected outline segments into continuous runs. Each resulting
        // path becomes its own stitch line.
        let leaves = selectedShapeIds
            .compactMap { findShape(id: $0) }
            .flatMap { leafShapes(of: $0) }
        let paths = StitchPathBuilder.build(from: leaves)
        guard !paths.isEmpty else { return }

        // Hybrid needs a split point, so open smooth runs wait for a click on the
        // path (pick mode) instead of committing now. Cornered/closed runs have no
        // hybrid split and are stitched immediately like any other mode.
        var immediate: [StitchPathBuilder.StitchPath] = []
        var pickable: [StitchPathBuilder.StitchPath] = []
        for path in paths {
            if selectedStitchMode == .hybrid,
               path.walker.cornerDistances.isEmpty, !path.walker.isClosed {
                pickable.append(path)
            } else {
                immediate.append(path)
            }
        }

        let holeCount = selectedStitchMode == .evenCount ? selectedStitchHoleCount : nil
        if !immediate.isEmpty {
            let old = document
            var added = false
            for path in immediate {
                let holes = AutoStitchEngine.generateHoles(
                    along: path.walker, iron: iron, mode: selectedStitchMode, holeCount: holeCount
                )
                guard !holes.isEmpty else { continue }
                activeLayer.stitchLines.append(
                    StitchLine(sourceShapeIds: path.sourceShapeIds, ironId: iron.id,
                               mode: selectedStitchMode, holeCount: holeCount, holes: holes)
                )
                added = true
            }
            if added { registerUndo(actionName: "Auto Stitch", oldDocument: old) }
        }

        if !pickable.isEmpty {
            pendingHybridRuns = pickable
            hybridPickPreview = nil
        }
    }

    // MARK: - Hybrid Stitch Pick (#23c)

    /// Project `point` onto `walker`: the arc-length of the closest path point plus the
    /// gap to it. Coarse sampling brackets the minimum, then a ternary search refines it
    /// (the gap is locally unimodal at that resolution).
    private func projectedDistance(of point: CGPoint, on walker: PathWalkable) -> (along: CGFloat, gap: CGFloat) {
        let total = walker.pathLength
        let samples = 256
        var bestAlong: CGFloat = 0
        var bestGap = CGFloat.greatestFiniteMagnitude
        for i in 0...samples {
            let d = total * CGFloat(i) / CGFloat(samples)
            let gap = walker.pointAtDistance(d).distance(to: point)
            if gap < bestGap {
                bestGap = gap
                bestAlong = d
            }
        }
        let step = total / CGFloat(samples)
        var lo = max(0, bestAlong - step)
        var hi = min(total, bestAlong + step)
        for _ in 0..<24 {
            let m1 = lo + (hi - lo) / 3
            let m2 = hi - (hi - lo) / 3
            if walker.pointAtDistance(m1).distance(to: point) <= walker.pointAtDistance(m2).distance(to: point) {
                hi = m2
            } else {
                lo = m1
            }
        }
        let along = (lo + hi) / 2
        return (along, walker.pointAtDistance(along).distance(to: point))
    }

    /// The pending run closest to `point`, with the projected arc-length on it.
    /// Cursors farther than ~20 screen px from every pending run return nil, so a
    /// stray click neither commits nor shows a ghost (the preview and the commit
    /// share this gate — what you see is what a click does).
    private func nearestHybridRun(to point: CGPoint) -> (index: Int, along: CGFloat)? {
        let tolerance = transform.screenToWorldDistance(20)
        var best: (index: Int, along: CGFloat, gap: CGFloat)?
        for (i, path) in pendingHybridRuns.enumerated() {
            let projected = projectedDistance(of: point, on: path.walker)
            if best == nil || projected.gap < best!.gap {
                best = (i, projected.along, projected.gap)
            }
        }
        guard let best, best.gap <= tolerance else { return nil }
        return (best.index, best.along)
    }

    /// Rebuild the ghost preview for the cursor at `point` (pick-mode mouse move).
    private func updateHybridPickPreview(at point: CGPoint) {
        guard let iron = activePrickingIron, let pick = nearestHybridRun(to: point) else {
            hybridPickPreview = nil
            return
        }
        let walker = pendingHybridRuns[pick.index].walker
        let holes = AutoStitchEngine.generateHoles(
            along: walker, iron: iron, mode: .hybrid, fixedLength: pick.along
        )
        hybridPickPreview = HybridPickPreview(
            holes: holes,
            splitPoint: walker.pointAtDistance(pick.along),
            splitAngle: walker.tangentAtDistance(pick.along),
            holeType: iron.holeType,
            holeSize: iron.holeSize
        )
    }

    /// Commit the pending run nearest the click: exact pitch up to the picked point,
    /// evened spacing beyond it. Each pending run commits with its own click; Escape
    /// cancels the rest (`cancelDrawing`).
    private func commitHybridPick(at point: CGPoint) {
        guard let iron = activePrickingIron, let pick = nearestHybridRun(to: point) else { return }
        let path = pendingHybridRuns[pick.index]
        let holes = AutoStitchEngine.generateHoles(
            along: path.walker, iron: iron, mode: .hybrid, fixedLength: pick.along
        )
        guard !holes.isEmpty else { return }
        let old = document
        activeLayer.stitchLines.append(
            StitchLine(sourceShapeIds: path.sourceShapeIds, ironId: iron.id,
                       mode: .hybrid, fixedLength: pick.along, holes: holes)
        )
        pendingHybridRuns.remove(at: pick.index)
        hybridPickPreview = nil
        registerUndo(actionName: "Auto Stitch", oldDocument: old)
    }

    // MARK: - Box Stitch (駒合わせ)

    /// The current selection resolved into exactly two stitch runs, A = the longer part.
    /// `selectedShapeIds` is an unordered set, so leaves are collected in document order
    /// and the pair sorted by path length to keep the A/B assignment deterministic.
    func boxStitchRuns() -> (a: StitchPathBuilder.StitchPath, b: StitchPathBuilder.StitchPath)? {
        // Cheap bail-out: `canBoxStitch` is read from view bodies, so this runs on
        // every document change — skip the layer scan + weld with nothing selected.
        guard !selectedShapeIds.isEmpty else { return nil }
        var leaves: [AnyShape] = []
        for layer in document.layers {
            for shape in layer.shapes where selectedShapeIds.contains(shape.id) {
                leaves.append(contentsOf: leafShapes(of: shape))
            }
        }
        let paths = StitchPathBuilder.build(from: leaves)
        guard paths.count == 2 else { return nil }
        let ordered = paths.sorted {
            if $0.walker.pathLength != $1.walker.pathLength {
                return $0.walker.pathLength > $1.walker.pathLength
            }
            return ($0.sourceShapeIds.first?.uuidString ?? "") < ($1.sourceShapeIds.first?.uuidString ?? "")
        }
        return (ordered[0], ordered[1])
    }

    var canBoxStitch: Bool { boxStitchRuns() != nil }

    /// Dry-run a box stitch for the given policy: what both parts would receive.
    /// Non-mutating; the sheet calls this on every input change to refresh its labels
    /// and the canvas ghost preview.
    func boxStitchEstimate(policy: BoxStitchPolicy) -> BoxStitchEstimate? {
        guard let iron = activePrickingIron, let runs = boxStitchRuns(),
              let proposal = BoxStitchMatcher.proposal(for: [runs.a, runs.b], iron: iron) else { return nil }

        let requested = proposal.requestedCount(for: policy)
        let resolved = proposal.resolvedCount(for: policy)

        func makeRun(_ path: StitchPathBuilder.StitchPath, naturalCount: Int) -> BoxStitchEstimate.Run {
            let holes = AutoStitchEngine.generateHoles(
                along: path.walker, iron: iron, mode: .evenCount, holeCount: resolved
            )
            let length = path.walker.pathLength
            let intervals = path.walker.isClosed ? holes.count : holes.count - 1
            return BoxStitchEstimate.Run(
                length: length,
                isClosed: path.walker.isClosed,
                cornerCount: AutoStitchEngine.normalizedCornerCount(along: path.walker),
                naturalCount: naturalCount,
                holes: holes,
                effectivePitch: intervals > 0 ? length / CGFloat(intervals) : 0,
                hasExistingStitchLine: hasStitchLine(forExactSources: path.sourceShapeIds),
                sourceShapeIds: path.sourceShapeIds
            )
        }
        return BoxStitchEstimate(
            runA: makeRun(runs.a, naturalCount: proposal.naturalCountA),
            runB: makeRun(runs.b, naturalCount: proposal.naturalCountB),
            requestedCount: requested,
            resolvedCount: resolved
        )
    }

    /// Commit a box stitch: both parts get `.evenCount` stitch lines with the same
    /// persisted count, so shape edits regenerate each side with the count intact.
    /// Runs are re-derived here (not taken from the sheet) so an undo that slipped in
    /// while the sheet was up can't commit stale geometry. Existing stitch lines on
    /// the same runs are replaced; one undo restores everything.
    /// Returns false when nothing was committed (runs no longer resolve, or the
    /// re-derived pair can't take matching counts) so the sheet can surface it.
    @discardableResult
    func applyBoxStitch(count: Int) -> Bool {
        guard let iron = activePrickingIron, let runs = boxStitchRuns() else { return false }
        let holesA = AutoStitchEngine.generateHoles(along: runs.a.walker, iron: iron, mode: .evenCount, holeCount: count)
        let holesB = AutoStitchEngine.generateHoles(along: runs.b.walker, iron: iron, mode: .evenCount, holeCount: count)
        guard !holesA.isEmpty, holesA.count == holesB.count else { return false }

        let old = document
        let targets = [Set(runs.a.sourceShapeIds), Set(runs.b.sourceShapeIds)]
        for li in document.layers.indices {
            document.layers[li].stitchLines.removeAll { targets.contains(Set($0.sourceShapeIds)) }
        }
        activeLayer.stitchLines.append(
            StitchLine(sourceShapeIds: runs.a.sourceShapeIds, ironId: iron.id,
                       mode: .evenCount, holeCount: holesA.count, holes: holesA)
        )
        activeLayer.stitchLines.append(
            StitchLine(sourceShapeIds: runs.b.sourceShapeIds, ironId: iron.id,
                       mode: .evenCount, holeCount: holesB.count, holes: holesB)
        )
        registerUndo(actionName: "Box Stitch", oldDocument: old)
        return true
    }

    /// Whether any layer holds a stitch line generated from exactly these source shapes.
    private func hasStitchLine(forExactSources ids: [UUID]) -> Bool {
        let idSet = Set(ids)
        return document.layers.contains { layer in
            layer.stitchLines.contains { Set($0.sourceShapeIds) == idSet }
        }
    }

    // MARK: - Pricking Iron CRUD

    func addPrickingIron(_ iron: PrickingIron) {
        let old = document
        document.prickingIrons.append(iron)
        selectedIronId = iron.id
        registerUndo(actionName: "Add Pricking Iron", oldDocument: old)
    }

    func updatePrickingIron(_ iron: PrickingIron) {
        let old = document
        if let index = document.prickingIrons.firstIndex(where: { $0.id == iron.id }) {
            document.prickingIrons[index] = iron
        }
        registerUndo(actionName: "Update Pricking Iron", oldDocument: old)
    }

    func deletePrickingIron(id: UUID) {
        let old = document
        document.prickingIrons.removeAll { $0.id == id }
        if selectedIronId == id {
            selectedIronId = document.prickingIrons.first?.id
        }
        registerUndo(actionName: "Delete Pricking Iron", oldDocument: old)
    }

    func removeStitchLine(id: UUID) {
        guard let idx = activeLayer.stitchLines.firstIndex(where: { $0.id == id }) else { return }
        let old = document
        activeLayer.stitchLines.remove(at: idx)
        registerUndo(actionName: "Remove Stitch", oldDocument: old)
    }

    // MARK: - Page Layout

    func addPage(at worldPoint: CGPoint) {
        let old = document
        let page = PrintPage(origin: worldPoint)
        document.settings.pageLayout.pages.append(page)
        selectedPageId = page.id
        registerUndo(actionName: "Add Page", oldDocument: old)
    }

    func deleteSelectedPage() {
        guard let id = selectedPageId else { return }
        let old = document
        document.settings.pageLayout.pages.removeAll { $0.id == id }
        selectedPageId = nil
        registerUndo(actionName: "Delete Page", oldDocument: old)
    }

    func selectPage(at worldPoint: CGPoint) -> Bool {
        let layout = document.settings.pageLayout
        for page in layout.pages.reversed() {
            if layout.pageFrame(for: page).contains(worldPoint) {
                selectedPageId = page.id
                return true
            }
        }
        selectedPageId = nil
        return false
    }

    func moveSelectedPage(by worldDelta: CGPoint) {
        guard let id = selectedPageId,
              let idx = document.settings.pageLayout.pages.firstIndex(where: { $0.id == id }) else { return }
        document.settings.pageLayout.pages[idx].origin.x += worldDelta.x
        document.settings.pageLayout.pages[idx].origin.y += worldDelta.y
    }

    func commitPageMove() {
        if let snapshot = pageMoveUndoSnapshot, snapshot != document {
            registerUndo(actionName: "Move Page", oldDocument: snapshot)
        }
        pageMoveUndoSnapshot = nil
    }

    func updatePageProperty(_ update: (inout PrintPage) -> Void) {
        guard let id = selectedPageId,
              let idx = document.settings.pageLayout.pages.firstIndex(where: { $0.id == id }) else { return }
        let old = document
        update(&document.settings.pageLayout.pages[idx])
        registerUndo(actionName: "Edit Page Property", oldDocument: old)
    }

    /// Mutate page-layout-wide settings (paper size, orientation, margin, overlap, etc.)
    /// routed through the ViewModel's undo helper so Redo works. Views must use this
    /// instead of calling `undoManager.registerUndo` inline.
    func updatePageLayout(actionName: String, _ update: (inout PageLayoutSettings) -> Void) {
        let old = document
        update(&document.settings.pageLayout)
        guard old != document else { return }
        registerUndo(actionName: actionName, oldDocument: old)
    }

    var selectedPage: PrintPage? {
        guard let id = selectedPageId else { return nil }
        return document.settings.pageLayout.pages.first { $0.id == id }
    }

    // MARK: - Align & Distribute

    enum AlignEdge {
        case left, right, top, bottom, centerH, centerV
    }

    func alignSelectedShapes(_ edge: AlignEdge) {
        let shapes = selectedShapes
        guard shapes.count >= 2 else { return }

        let boxes = shapes.map { ($0.id, $0.boundingBox) }
        let old = document

        for (id, box) in boxes {
            guard let (li, si) = findShapeLocation(id: id) else { continue }
            var delta = CGPoint.zero
            switch edge {
            case .left:
                let target = boxes.map(\.1.minX).min()!
                delta.x = target - box.minX
            case .right:
                let target = boxes.map(\.1.maxX).max()!
                delta.x = target - box.maxX
            case .top:
                let target = boxes.map(\.1.minY).min()!
                delta.y = target - box.minY
            case .bottom:
                let target = boxes.map(\.1.maxY).max()!
                delta.y = target - box.maxY
            case .centerH:
                let combined = selectionBoundingBox!
                let target = combined.midY
                delta.y = target - box.midY
            case .centerV:
                let combined = selectionBoundingBox!
                let target = combined.midX
                delta.x = target - box.midX
            }
            if delta.x != 0 || delta.y != 0 {
                let ids = collectShapeIds(in: document.layers[li].shapes[si])
                document.layers[li].shapes[si].translate(by: delta)
                translateStitchHoles(forShapeIds: ids, by: delta)
            }
        }

        guard old != document else { return }
        registerUndo(actionName: "Align", oldDocument: old)
    }

    enum DistributeDirection {
        case horizontal, vertical
    }

    func distributeSelectedShapes(_ direction: DistributeDirection) {
        let shapes = selectedShapes
        guard shapes.count >= 3 else { return }

        let sorted: [(UUID, CGRect)]
        switch direction {
        case .horizontal:
            sorted = shapes.map { ($0.id, $0.boundingBox) }.sorted { $0.1.midX < $1.1.midX }
        case .vertical:
            sorted = shapes.map { ($0.id, $0.boundingBox) }.sorted { $0.1.midY < $1.1.midY }
        }

        let old = document

        switch direction {
        case .horizontal:
            let totalWidth = sorted.reduce(CGFloat(0)) { $0 + $1.1.width }
            let spanMin = sorted.first!.1.minX
            let spanMax = sorted.last!.1.maxX
            let totalSpace = (spanMax - spanMin) - totalWidth
            let gap = totalSpace / CGFloat(sorted.count - 1)

            var currentX = spanMin
            for (id, box) in sorted {
                let dx = currentX - box.minX
                if dx != 0, let (li, si) = findShapeLocation(id: id) {
                    let ids = collectShapeIds(in: document.layers[li].shapes[si])
                    let delta = CGPoint(x: dx, y: 0)
                    document.layers[li].shapes[si].translate(by: delta)
                    translateStitchHoles(forShapeIds: ids, by: delta)
                }
                currentX += box.width + gap
            }

        case .vertical:
            let totalHeight = sorted.reduce(CGFloat(0)) { $0 + $1.1.height }
            let spanMin = sorted.first!.1.minY
            let spanMax = sorted.last!.1.maxY
            let totalSpace = (spanMax - spanMin) - totalHeight
            let gap = totalSpace / CGFloat(sorted.count - 1)

            var currentY = spanMin
            for (id, box) in sorted {
                let dy = currentY - box.minY
                if dy != 0, let (li, si) = findShapeLocation(id: id) {
                    let ids = collectShapeIds(in: document.layers[li].shapes[si])
                    let delta = CGPoint(x: 0, y: dy)
                    document.layers[li].shapes[si].translate(by: delta)
                    translateStitchHoles(forShapeIds: ids, by: delta)
                }
                currentY += box.height + gap
            }
        }

        guard old != document else { return }
        registerUndo(actionName: "Distribute", oldDocument: old)
    }

    // MARK: - Mirror

    enum MirrorAxisKind {
        case horizontal  // y 一定の横軸（上下反転）
        case vertical    // x 一定の縦軸（左右反転）
    }

    /// Reflect the current selection across an axis derived from the selection bounding box.
    /// In-place mirror reflects across the bbox center; copy mode reflects across the bbox edge,
    /// producing a duplicate that sits flush against the original.
    func mirrorSelectedShapes(_ kind: MirrorAxisKind, copy: Bool) {
        guard hasSelection, let bbox = selectionBoundingBox else { return }
        // For copy mode use the visual bbox so the duplicate sits flush against
        // the rendered edge (Bezier handles / Arc full-circle padding would
        // otherwise leave a gap). In-place stays on the geometric bbox so the
        // mirror axis matches the visible selection rectangle the user sees.
        let copyBBox = selectionVisualBoundingBox ?? bbox
        let axis: MirrorAxis
        switch (kind, copy) {
        case (.vertical, false):   axis = .vertical(x: bbox.midX)
        case (.horizontal, false): axis = .horizontal(y: bbox.midY)
        case (.vertical, true):    axis = .vertical(x: copyBBox.maxX)
        case (.horizontal, true):  axis = .horizontal(y: copyBBox.maxY)
        }

        let old = document
        let actionName = copy ? "Mirror Copy" : "Mirror"

        if copy {
            var newSelection: Set<UUID> = []
            for id in Array(selectedShapeIds) {
                guard let (li, si) = findShapeLocation(id: id) else { continue }
                let original = document.layers[li].shapes[si]
                let (cloned, idMap) = cloneWithFreshIds(original)
                var mirroredClone = cloned
                mirroredClone.mirror(axis: axis)
                document.layers[li].shapes.insert(mirroredClone, at: si + 1)
                duplicateStitchLines(inLayer: li, idMap: idMap)
                newSelection.formUnion(idMap.values)
            }
            selectedShapeIds = newSelection
            regenerateStitchLines(forShapeIds: newSelection)
        } else {
            var affectedIds: Set<UUID> = []
            for id in selectedShapeIds {
                guard let (li, si) = findShapeLocation(id: id) else { continue }
                affectedIds.formUnion(collectShapeIds(in: document.layers[li].shapes[si]))
                document.layers[li].shapes[si].mirror(axis: axis)
            }
            regenerateStitchLines(forShapeIds: affectedIds)
        }

        guard old != document else { return }
        registerUndo(actionName: actionName, oldDocument: old)
    }

    // MARK: - Array

    struct ArrayParameters: Equatable {
        enum Mode { case linear, grid, polar }
        var mode: Mode
        // Linear: total count including the original (>= 2)
        var count: Int
        var offsetX: CGFloat
        var offsetY: CGFloat
        // Grid: rows × cols including the original (>= 1)
        var rows: Int
        var cols: Int
        var rowSpacing: CGFloat
        var colSpacing: CGFloat
        // Polar: total count including the original (>= 2), radius (mm),
        // start angle and sweep angle in degrees, optional item rotation
        var polarCount: Int
        var polarRadius: CGFloat
        var polarStartAngle: CGFloat
        var polarSweepAngle: CGFloat
        var polarRotateItems: Bool

        static let `default` = ArrayParameters(
            mode: .linear,
            count: 5,
            offsetX: 10,
            offsetY: 0,
            rows: 3,
            cols: 3,
            rowSpacing: 5,
            colSpacing: 5,
            polarCount: 6,
            polarRadius: 30,
            polarStartAngle: 0,
            polarSweepAngle: 360,
            polarRotateItems: true
        )
    }

    /// One placement in an array operation: where to translate the clone, and
    /// how much extra to rotate it about its own new center. Linear/Grid use
    /// rotation = 0; Polar uses both.
    private struct ArrayPlacement {
        var offset: CGPoint
        var rotation: CGFloat  // radians
    }

    /// Replicate the current selection in a linear or rectangular grid pattern.
    /// The original shapes stay in place; clones are inserted into the same layer at each
    /// non-zero offset. Stitch lines on the originals are duplicated and regenerated for
    /// each clone via the same path Mirror uses.
    func arraySelectedShapes(_ params: ArrayParameters) {
        guard hasSelection, let bbox = selectionBoundingBox else { return }
        let placements = computeArrayPlacements(params: params, bbox: bbox)
        guard !placements.isEmpty else { return }

        let old = document
        let pivot = CGPoint(x: bbox.midX, y: bbox.midY)

        // Snapshot the originals so we don't iterate over clones we just inserted.
        var originals: [(li: Int, shape: AnyShape)] = []
        for id in selectedShapeIds {
            if let (li, si) = findShapeLocation(id: id) {
                originals.append((li, document.layers[li].shapes[si]))
            }
        }

        var newSelection: Set<UUID> = []
        for placement in placements {
            for (li, shape) in originals {
                let (cloned, idMap) = cloneWithFreshIds(shape)
                var moved = cloned
                if placement.rotation != 0 {
                    // Rotate around the selection bbox center first, then translate.
                    // Translating first would move the rotation pivot away from
                    // the bbox center and produce wrong placements.
                    moved.rotate(around: pivot, angle: placement.rotation)
                }
                moved.translate(by: placement.offset)
                document.layers[li].shapes.append(moved)
                duplicateStitchLines(inLayer: li, idMap: idMap)
                newSelection.formUnion(idMap.values)
            }
        }

        // Keep the originals selected and add the clones — convenient for repeat operations.
        selectedShapeIds.formUnion(newSelection)
        regenerateStitchLines(forShapeIds: newSelection)

        guard old != document else { return }
        registerUndo(actionName: "Array", oldDocument: old)
    }

    private func computeArrayPlacements(params: ArrayParameters, bbox: CGRect) -> [ArrayPlacement] {
        switch params.mode {
        case .linear:
            guard params.count > 1 else { return [] }
            return (1..<params.count).map { i in
                ArrayPlacement(
                    offset: CGPoint(x: CGFloat(i) * params.offsetX,
                                    y: CGFloat(i) * params.offsetY),
                    rotation: 0
                )
            }
        case .grid:
            guard params.rows >= 1, params.cols >= 1 else { return [] }
            let dx = bbox.width + params.colSpacing
            let dy = bbox.height + params.rowSpacing
            var result: [ArrayPlacement] = []
            for r in 0..<params.rows {
                for c in 0..<params.cols {
                    if r == 0 && c == 0 { continue }
                    result.append(ArrayPlacement(
                        offset: CGPoint(x: CGFloat(c) * dx, y: CGFloat(r) * dy),
                        rotation: 0
                    ))
                }
            }
            return result
        case .polar:
            guard params.polarCount > 1 else { return [] }
            // The original sits at angle 0 around the bbox center; clones are
            // produced by rotating the original by stepRad about that center.
            // Sweep == 360 distributes count copies around the full circle;
            // smaller sweeps distribute the copies including endpoints (so
            // count = N puts copies at 0/sweep/N-1, 2*sweep/N-1, … sweep).
            let isFullCircle = abs(params.polarSweepAngle - 360) < 0.001
            let stepDeg = isFullCircle
                ? params.polarSweepAngle / CGFloat(params.polarCount)
                : params.polarSweepAngle / CGFloat(max(params.polarCount - 1, 1))
            // The original "starts" at polarStartAngle along the radius. To put
            // it on the radius circle we offset it by the start vector first,
            // then rotate copies.
            let startRad = params.polarStartAngle * .pi / 180
            let baseOffset = CGPoint(
                x: params.polarRadius * cos(startRad),
                y: params.polarRadius * sin(startRad)
            )
            var result: [ArrayPlacement] = []
            for i in 1..<params.polarCount {
                let stepRad = (stepDeg * CGFloat(i)) * .pi / 180
                // Rotate the base offset by stepRad around the origin to find
                // where this clone's center should be relative to the original.
                let rotatedTip = baseOffset.rotated(around: .zero, angle: stepRad)
                let cloneOffset = CGPoint(x: rotatedTip.x - baseOffset.x,
                                          y: rotatedTip.y - baseOffset.y)
                result.append(ArrayPlacement(
                    offset: cloneOffset,
                    rotation: params.polarRotateItems ? stepRad : 0
                ))
            }
            return result
        }
    }

    /// Deep-copy a shape with fresh UUIDs at every level (groups recurse).
    /// Returns the clone and a map of original-id → new-id covering this shape and all descendants.
    private func cloneWithFreshIds(_ shape: AnyShape) -> (clone: AnyShape, idMap: [UUID: UUID]) {
        var idMap: [UUID: UUID] = [:]
        let clone = recursiveClone(shape, idMap: &idMap)
        return (clone, idMap)
    }

    private func recursiveClone(_ shape: AnyShape, idMap: inout [UUID: UUID]) -> AnyShape {
        let newId = UUID()
        idMap[shape.id] = newId
        switch shape {
        case .line(let s):
            var c = LineShape(id: newId, start: s.startPoint, end: s.endPoint, stroke: s.stroke)
            c.isLocked = s.isLocked
            return .line(c)
        case .rectangle(let s):
            var c = RectangleShape(id: newId, origin: s.origin, size: s.size, cornerRadius: s.cornerRadius, rotation: s.rotation, stroke: s.stroke)
            c.isLocked = s.isLocked
            return .rectangle(c)
        case .ellipse(let s):
            var c = EllipseShape(id: newId, center: s.center, radiusX: s.radiusX, radiusY: s.radiusY, stroke: s.stroke)
            c.rotation = s.rotation
            c.isLocked = s.isLocked
            return .ellipse(c)
        case .arc(let s):
            var c = ArcShape(id: newId, center: s.center, radius: s.radius,
                             startAngle: s.startAngle, endAngle: s.endAngle,
                             clockwise: s.clockwise, stroke: s.stroke)
            c.isLocked = s.isLocked
            return .arc(c)
        case .dot(let s):
            var c = DotShape(id: newId, position: s.position, radius: s.radius, stroke: s.stroke)
            c.isLocked = s.isLocked
            return .dot(c)
        case .bezier(let s):
            var c = BezierShape(id: newId, points: s.points, isClosed: s.isClosed, stroke: s.stroke)
            c.isLocked = s.isLocked
            return .bezier(c)
        case .text(let s):
            var c = TextShape(id: newId, position: s.position, content: s.content,
                              fontSize: s.fontSize, fontName: s.fontName,
                              isBold: s.isBold, isItalic: s.isItalic,
                              textAlignment: s.textAlignment, rotation: s.rotation, stroke: s.stroke)
            c.isLocked = s.isLocked
            return .text(c)
        case .dimensionLine(let s):
            var c = DimensionLineShape(id: newId, start: s.start, end: s.end, offset: s.offset,
                                       kind: s.kind, labelOverride: s.labelOverride, stroke: s.stroke)
            c.isLocked = s.isLocked
            return .dimensionLine(c)
        case .group(let s):
            let clonedChildren = s.children.map { recursiveClone($0, idMap: &idMap) }
            var c = GroupShape(id: newId, children: clonedChildren)
            c.isLocked = s.isLocked
            return .group(c)
        }
    }

    /// Duplicate stitch lines whose source shape was cloned. Holes are left empty—
    /// the caller is expected to invoke `regenerateStitchLines` after the new shapes
    /// have been inserted so PathWalker can resolve the new geometry.
    private func duplicateStitchLines(inLayer li: Int, idMap: [UUID: UUID]) {
        let originals = document.layers[li].stitchLines.filter { line in
            line.sourceShapeIds.allSatisfy { idMap.keys.contains($0) }
        }
        for line in originals {
            let newSourceIds = line.sourceShapeIds.compactMap { idMap[$0] }
            guard newSourceIds.count == line.sourceShapeIds.count else { continue }
            let newLine = StitchLine(
                id: UUID(),
                sourceShapeIds: newSourceIds,
                ironId: line.ironId,
                mode: line.mode,
                holes: []
            )
            document.layers[li].stitchLines.append(newLine)
        }
    }

    // MARK: - Templates

    /// Build a template from the current selection without touching the library.
    /// Shapes are cloned with fresh IDs and normalized so their combined bounding
    /// box is centered on the origin. When `asGroup` is true they are wrapped in a
    /// single `GroupShape`; otherwise the flattened shapes are stored as-is.
    /// Returns nil when nothing is selected.
    func buildTemplate(name: String, asGroup: Bool) -> Template? {
        // Gather selected shapes preserving each layer's z-order (selection may span layers).
        var gathered: [AnyShape] = []
        for layer in document.layers {
            for shape in layer.shapes where selectedShapeIds.contains(shape.id) {
                gathered.append(shape)
            }
        }
        guard !gathered.isEmpty else { return nil }

        var clones = gathered.map { cloneWithFreshIds($0).clone }
        guard let box = clones.combinedBoundingBox else { return nil }
        let recenter = CGPoint(x: -box.midX, y: -box.midY)
        for i in clones.indices { clones[i].translate(by: recenter) }

        let stored: [AnyShape] = asGroup ? [.group(GroupShape(children: clones))] : clones

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty
            ? "Template \(TemplateLibraryStore.shared.templates.count + 1)"
            : trimmed
        return Template(name: finalName, shapes: stored)
    }

    /// Build a template from the current selection and add it to the global library.
    func saveSelectionAsTemplate(name: String, asGroup: Bool) {
        guard let template = buildTemplate(name: name, asGroup: asGroup) else { return }
        TemplateLibraryStore.shared.add(template)
    }

    /// Enter click-to-place mode for the given template. The next canvas click
    /// places it; a cursor-following ghost is drawn until then.
    func beginTemplatePlacement(_ template: Template) {
        currentTool = .select
        selectedShapeIds = []
        drawingPreview = nil
        marqueeStart = nil
        marqueeRect = nil
        pendingTemplate = template
    }

    /// Place a template's shapes into the active layer, centered on `worldPoint`.
    /// Each placement clones with fresh IDs so repeated drops never share IDs.
    func placeTemplate(_ template: Template, at worldPoint: CGPoint) {
        guard !template.shapes.isEmpty else { return }
        let old = document
        var placedIds: Set<UUID> = []
        for shape in template.shapes {
            var clone = cloneWithFreshIds(shape).clone
            clone.translate(by: worldPoint)
            activeLayer.shapes.append(clone)
            placedIds.insert(clone.id)
        }
        selectedShapeIds = placedIds
        registerUndo(actionName: "Place Template", oldDocument: old)
    }

    // MARK: - Export

    func exportSVG() {
        ExportCoordinator.exportSVG(document: document)
    }

    func exportDXF() {
        ExportCoordinator.exportDXF(document: document)
    }
}

