import SwiftUI

struct CanvasView: View {
    @Bindable var editor: EditorViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // 1. Grid
                let gridRenderer = GridRenderer(
                    settings: editor.document.settings,
                    transform: editor.transform,
                    colorScheme: colorScheme
                )
                gridRenderer.draw(in: context, size: size)

                // 2. Committed shapes
                let renderer = CanvasRenderer(transform: editor.transform)
                for layer in editor.document.layers where layer.isVisible {
                    for shape in layer.shapes {
                        renderer.draw(shape: shape, in: context)
                    }
                }

                // 2.5. Stitch holes
                for layer in editor.document.layers where layer.isVisible {
                    for stitchLine in layer.stitchLines {
                        if let iron = editor.document.prickingIrons.first(where: { $0.id == stitchLine.ironId }) {
                            for hole in stitchLine.holes {
                                renderer.drawStitchHole(hole, holeType: iron.holeType, holeSize: iron.holeSize, in: context)
                            }
                        }
                    }
                }

                // 3. Drawing preview (in-progress shape)
                DrawingPreviewRenderer.draw(
                    preview: editor.drawingPreview,
                    transform: editor.transform,
                    in: context
                )

                // 4. Snap indicator
                SnapOverlay.draw(
                    candidate: editor.activeSnapCandidate,
                    transform: editor.transform,
                    in: context
                )

                // 5. Selection overlay
                if let selectedId = editor.selectedShapeId,
                   let shape = editor.findShape(id: selectedId) {
                    if case .bezier(let bezier) = shape {
                        SelectionOverlay.drawBezierEditOverlay(
                            bezier: bezier,
                            transform: editor.transform,
                            draggingIndex: editor.draggingBezierPointIndex,
                            draggingTarget: editor.draggingBezierTarget,
                            in: context
                        )
                    } else {
                        SelectionOverlay.draw(
                            boundingBox: shape.boundingBox,
                            transform: editor.transform,
                            in: context
                        )
                    }
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                editor.canvasSize = newSize
            }
            .onAppear { editor.canvasSize = geometry.size }
            .background(DesignTokens.bgCanvas(colorScheme))
            .scrollZoom(editor: editor)
            .gesture(makePanGesture(canvasSize: geometry.size))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    editor.handleMouseMove(screenPoint: location)
                case .ended:
                    break
                }
            }
            .onTapGesture { location in
                editor.handleClick(at: location)
            }
            .onKeyPress(.escape) {
                editor.cancelDrawing()
                return .handled
            }
            .onKeyPress(.return) {
                if editor.currentTool == .bezier {
                    editor.commitBezier()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(phases: .down) { keyPress in
                // Single-key tool shortcuts (Photoshop style)
                switch keyPress.characters.lowercased() {
                case "v": editor.selectTool(.select); return .handled
                case "l": editor.selectTool(.line); return .handled
                case "r": editor.selectTool(.rectangle); return .handled
                case "e": editor.selectTool(.ellipse); return .handled
                case "a": editor.selectTool(.arc); return .handled
                case "p": editor.selectTool(.bezier); return .handled
                case "t": editor.selectTool(.text); return .handled
                default: return .ignored
                }
            }
        }
    }

    private func makePanGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let delta = CGPoint(
                    x: value.translation.width - (editor.lastPanTranslation?.width ?? 0),
                    y: value.translation.height - (editor.lastPanTranslation?.height ?? 0)
                )
                let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                if editor.currentTool == .select && editor.selectedShapeId != nil {
                    if editor.draggingBezierPointIndex != nil {
                        // Continue bezier point drag
                        editor.dragBezierPoint(to: value.location, shiftHeld: shiftHeld)
                    } else if editor.lastPanTranslation == nil {
                        // First drag event: try bezier point drag first
                        if editor.startBezierPointDrag(startScreenPoint: value.startLocation) {
                            editor.dragBezierPoint(to: value.location, shiftHeld: shiftHeld)
                        } else {
                            // Normal shape move
                            editor.moveUndoSnapshot = editor.document
                            let worldDelta = CGPoint(
                                x: delta.x / editor.transform.scale,
                                y: delta.y / editor.transform.scale
                            )
                            editor.moveSelectedShape(by: worldDelta)
                        }
                    } else {
                        // Continue normal shape move
                        let worldDelta = CGPoint(
                            x: delta.x / editor.transform.scale,
                            y: delta.y / editor.transform.scale
                        )
                        editor.moveSelectedShape(by: worldDelta)
                    }
                    editor.updateEdgeScroll(cursorScreenPoint: value.location, canvasSize: canvasSize)
                } else if editor.currentTool == .select {
                    editor.transform.pan(by: delta)
                } else {
                    editor.handleDrag(startLocation: value.startLocation, currentLocation: value.location, phase: .changed, shiftHeld: shiftHeld)
                }
                editor.lastPanTranslation = value.translation
            }
            .onEnded { value in
                editor.stopEdgeScroll()
                if editor.draggingBezierPointIndex != nil {
                    editor.endBezierPointDrag()
                } else if editor.currentTool == .select && editor.selectedShapeId != nil {
                    if let snapshot = editor.moveUndoSnapshot {
                        editor.commitMoveWithUndo(oldDocument: snapshot)
                        editor.moveUndoSnapshot = nil
                    }
                } else if editor.currentTool != .select || editor.selectedShapeId == nil {
                    let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                    editor.handleDrag(startLocation: value.startLocation, currentLocation: value.location, phase: .ended, shiftHeld: shiftHeld)
                }
                editor.lastPanTranslation = nil
            }
    }
}
