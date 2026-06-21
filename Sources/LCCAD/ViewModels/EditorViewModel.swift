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
        case .bevel: return "arrow.turn.up.right"
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
    var activeLayerIndex: Int = 0

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
    var showPrickingIronSheet: Bool = false

    // Array sheet state
    var showArraySheet: Bool = false

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
        // so they track with the cursor position (skip during bezier point drag)
        if hasSelection && draggingBezierPointIndex == nil {
            moveSelectedShapes(by: CGPoint(x: -d.x, y: -d.y))
        }
    }

    // MARK: - Layer Access

    var activeLayer: Layer {
        get { document.layers[activeLayerIndex] }
        set { document.layers[activeLayerIndex] = newValue }
    }

    // MARK: - Undo Support

    private func registerUndo(actionName: String, oldDocument: DocumentData) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            let redoDoc = target.document
            target.document = oldDocument
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
        guard oldDocument != document else { return }
        registerUndo(actionName: "Move Shape", oldDocument: oldDocument)
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

    /// Shift every stitch hole whose `sourceShapeId` is in `ids` by `delta`.
    private func translateStitchHoles(forShapeIds ids: Set<UUID>, by delta: CGPoint) {
        guard !ids.isEmpty, delta.x != 0 || delta.y != 0 else { return }
        for li in document.layers.indices {
            for si in document.layers[li].stitchLines.indices
            where ids.contains(document.layers[li].stitchLines[si].sourceShapeId) {
                for hi in document.layers[li].stitchLines[si].holes.indices {
                    document.layers[li].stitchLines[si].holes[hi].position.x += delta.x
                    document.layers[li].stitchLines[si].holes[hi].position.y += delta.y
                }
            }
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
        for li in document.layers.indices {
            var si = 0
            while si < document.layers[li].stitchLines.count {
                let line = document.layers[li].stitchLines[si]
                guard ids.contains(line.sourceShapeId) else { si += 1; continue }

                if let shape = findShape(id: line.sourceShapeId),
                   let walker = PathWalkerFactory.walker(for: shape) {
                    if let iron = document.prickingIrons.first(where: { $0.id == line.ironId }) {
                        document.layers[li].stitchLines[si].holes =
                            AutoStitchEngine.generateHoles(along: walker, iron: iron, mode: line.mode)
                    }
                    si += 1
                } else {
                    document.layers[li].stitchLines.remove(at: si)
                }
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
            // Click on a line to bevel its corner
            if let hitId = hitTest(at: worldPoint, tolerance: tolerance) {
                selectedShapeIds = [hitId]
                bevelCorner(radius: 2.0)
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

    func moveSelectedShapes(by worldDelta: CGPoint) {
        var movedIds: Set<UUID> = []
        for id in selectedShapeIds {
            if let (li, si) = findShapeLocation(id: id) {
                movedIds.formUnion(collectShapeIds(in: document.layers[li].shapes[si]))
                document.layers[li].shapes[si].translate(by: worldDelta)
            }
        }
        translateStitchHoles(forShapeIds: movedIds, by: worldDelta)
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
            document.layers[li].stitchLines = layer.stitchLines.filter { !idsToDelete.contains($0.sourceShapeId) }
        }
        selectedShapeIds = []
        registerUndo(actionName: "Delete Shape", oldDocument: old)
    }

    func cancelDrawing() {
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

    /// Bevel (round corner) between two selected lines.
    func bevelCorner(radius: CGFloat) {
        // For now, bevel requires exactly two lines to be adjacent
        // This is a simplified version — the user selects a line, and we find the adjacent one
        guard let id = selectedShapeIds.first,
              let (li, si) = findShapeLocation(id: id),
              case .line(let line1) = document.layers[li].shapes[si] else { return }

        // Find an adjacent line
        for (si2, shape) in document.layers[li].shapes.enumerated() {
            guard si2 != si, case .line(let line2) = shape else { continue }
            if let result = BevelTool.bevel(line1: line1, line2: line2, radius: radius) {
                let old = document
                // Preserve original ids so stitch lines keep tracking each shortened line.
                let preservedLine1 = LineShape(id: line1.id,
                                               start: result.line1.startPoint,
                                               end: result.line1.endPoint,
                                               stroke: result.line1.stroke)
                let preservedLine2 = LineShape(id: line2.id,
                                               start: result.line2.startPoint,
                                               end: result.line2.endPoint,
                                               stroke: result.line2.stroke)
                document.layers[li].shapes[si] = .line(preservedLine1)
                document.layers[li].shapes[si2] = .line(preservedLine2)
                document.layers[li].shapes.append(.arc(result.arc))
                regenerateStitchLines(forShapeIds: [line1.id, line2.id])
                registerUndo(actionName: "Bevel Corner", oldDocument: old)
                return
            }
        }
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

    func autoStitchSelectedShape() {
        guard let id = selectedShapeIds.first,
              let shape = findShape(id: id),
              let iron = activePrickingIron else { return }

        guard let walker = PathWalkerFactory.walker(for: shape) else { return }

        let holes = AutoStitchEngine.generateHoles(along: walker, iron: iron)
        let stitchLine = StitchLine(sourceShapeId: id, ironId: iron.id, holes: holes)

        let old = document
        activeLayer.stitchLines.append(stitchLine)
        registerUndo(actionName: "Auto Stitch", oldDocument: old)
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
        let originals = document.layers[li].stitchLines.filter { idMap.keys.contains($0.sourceShapeId) }
        for line in originals {
            guard let newSourceId = idMap[line.sourceShapeId] else { continue }
            let newLine = StitchLine(
                id: UUID(),
                sourceShapeId: newSourceId,
                ironId: line.ironId,
                mode: line.mode,
                holes: []
            )
            document.layers[li].stitchLines.append(newLine)
        }
    }

    // MARK: - Export

    func exportSVG() {
        ExportCoordinator.exportSVG(document: document)
    }

    func exportDXF() {
        ExportCoordinator.exportDXF(document: document)
    }
}

