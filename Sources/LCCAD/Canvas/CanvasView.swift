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

                // 3.5. Page layout overlay
                let pageLayout = editor.document.settings.pageLayout
                if pageLayout.showPageFrames || editor.currentTool == .page {
                    PageLayoutOverlay.draw(
                        layout: pageLayout,
                        selectedPageId: editor.selectedPageId,
                        transform: editor.transform,
                        colorScheme: colorScheme,
                        in: context
                    )
                }

                // 4. Snap indicator
                SnapOverlay.draw(
                    candidate: editor.activeSnapCandidate,
                    transform: editor.transform,
                    in: context
                )

                // 5. Selection overlay
                if editor.isSingleSelection,
                   let id = editor.selectedShapeIds.first,
                   let shape = editor.findShape(id: id) {
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
                } else if editor.isMultiSelection {
                    // Draw individual bounding boxes for each selected shape
                    for id in editor.selectedShapeIds {
                        if let shape = editor.findShape(id: id) {
                            SelectionOverlay.drawLightBoundingBox(
                                boundingBox: shape.boundingBox,
                                transform: editor.transform,
                                in: context
                            )
                        }
                    }
                    // Draw combined bounding box
                    if let combinedBox = editor.selectionBoundingBox {
                        SelectionOverlay.draw(
                            boundingBox: combinedBox,
                            transform: editor.transform,
                            in: context
                        )
                    }
                }

                // 6. Marquee selection rectangle
                if let marqueeRect = editor.marqueeRect {
                    SelectionOverlay.drawMarquee(rect: marqueeRect, in: context)
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
                let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                editor.handleClick(at: location, shiftHeld: shiftHeld)
            }
            .onDeleteCommand {
                if editor.currentTool == .page && editor.selectedPageId != nil {
                    editor.deleteSelectedPage()
                } else if editor.hasSelection {
                    editor.deleteSelectedShapes()
                }
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

                if editor.currentTool == .page {
                    if editor.lastPanTranslation == nil {
                        // First drag: select page and start tracking raw origin
                        let worldPoint = editor.transform.screenToWorld(value.startLocation)
                        if editor.selectPage(at: worldPoint) {
                            editor.pageMoveUndoSnapshot = editor.document
                            if let id = editor.selectedPageId,
                               let page = editor.document.settings.pageLayout.pages.first(where: { $0.id == id }) {
                                editor.pageDragRawOrigin = page.origin
                            }
                        }
                    }
                    if editor.selectedPageId != nil, editor.pageDragRawOrigin != nil {
                        let worldDelta = CGPoint(
                            x: delta.x / editor.transform.scale,
                            y: delta.y / editor.transform.scale
                        )
                        // Update raw (unsnapped) origin
                        editor.pageDragRawOrigin!.x += worldDelta.x
                        editor.pageDragRawOrigin!.y += worldDelta.y
                        let rawOrigin = editor.pageDragRawOrigin!

                        if let id = editor.selectedPageId,
                           let idx = editor.document.settings.pageLayout.pages.firstIndex(where: { $0.id == id }) {
                            let layout = editor.document.settings.pageLayout
                            let otherOrigins = layout.pages.filter { $0.id != id }.map(\.origin)
                            let tolerance = editor.transform.screenToWorldDistance(8)

                            // 1. Page-to-page snap (priority)
                            let pageResult = PageSnapEngine.snap(
                                draggedOrigin: rawOrigin,
                                pageSize: layout.effectivePageSize,
                                allOtherOrigins: otherOrigins,
                                overlapMM: layout.overlapMM,
                                tolerance: tolerance
                            )
                            var origin = pageResult.snappedOrigin

                            // 2. Grid snap fallback for axes not page-snapped
                            if editor.document.settings.snapToGrid {
                                let gridRenderer = GridRenderer(
                                    settings: editor.document.settings,
                                    transform: editor.transform,
                                    colorScheme: colorScheme
                                )
                                let (fineSpacing, _) = gridRenderer.adaptiveSpacings()
                                if !pageResult.snappedX {
                                    let gridX = (rawOrigin.x / fineSpacing).rounded() * fineSpacing
                                    if abs(gridX - rawOrigin.x) < tolerance {
                                        origin.x = gridX
                                    }
                                }
                                if !pageResult.snappedY {
                                    let gridY = (rawOrigin.y / fineSpacing).rounded() * fineSpacing
                                    if abs(gridY - rawOrigin.y) < tolerance {
                                        origin.y = gridY
                                    }
                                }
                            }

                            editor.document.settings.pageLayout.pages[idx].origin = origin
                        }
                    }
                } else if editor.currentTool == .select {
                    if editor.draggingBezierPointIndex != nil {
                        // Continue bezier point drag
                        editor.dragBezierPoint(to: value.location, shiftHeld: shiftHeld)
                    } else if editor.marqueeStart != nil {
                        // Continue marquee selection
                        editor.updateMarquee(to: value.location, shiftHeld: shiftHeld)
                    } else if editor.lastPanTranslation == nil {
                        // First drag event: determine what to do.
                        // Try bezier handle/anchor drag first — handles can sit far from the curve outline,
                        // so the general shape hit test below would miss them.
                        if editor.startBezierPointDrag(startScreenPoint: value.startLocation) {
                            editor.dragBezierPoint(to: value.location, shiftHeld: shiftHeld)
                        } else {
                            let worldPoint = editor.transform.screenToWorld(value.startLocation)
                            let tolerance = editor.transform.screenToWorldDistance(5)
                            let hitId = editor.hitTestPublic(at: worldPoint, tolerance: tolerance)

                            if let hitId = hitId, editor.selectedShapeIds.contains(hitId) {
                                // Drag on a selected shape: start move
                                editor.moveUndoSnapshot = editor.document
                                let worldDelta = CGPoint(
                                    x: delta.x / editor.transform.scale,
                                    y: delta.y / editor.transform.scale
                                )
                                editor.moveSelectedShapes(by: worldDelta)
                            } else if let hitId = hitId {
                                // Drag on an unselected shape: select it first, then start move
                                if shiftHeld {
                                    editor.selectedShapeIds.insert(hitId)
                                } else {
                                    editor.selectedShapeIds = [hitId]
                                }
                                editor.moveUndoSnapshot = editor.document
                                let worldDelta = CGPoint(
                                    x: delta.x / editor.transform.scale,
                                    y: delta.y / editor.transform.scale
                                )
                                editor.moveSelectedShapes(by: worldDelta)
                            } else {
                                // Drag on empty area: start marquee selection
                                if !shiftHeld {
                                    editor.selectedShapeIds = []
                                }
                                editor.beginMarquee(at: value.startLocation)
                                editor.updateMarquee(to: value.location, shiftHeld: shiftHeld)
                            }
                        }
                    } else if editor.hasSelection && editor.marqueeStart == nil {
                        // Continue normal shape move
                        let worldDelta = CGPoint(
                            x: delta.x / editor.transform.scale,
                            y: delta.y / editor.transform.scale
                        )
                        editor.moveSelectedShapes(by: worldDelta)
                    }

                    if editor.hasSelection && editor.marqueeStart == nil {
                        editor.updateEdgeScroll(cursorScreenPoint: value.location, canvasSize: canvasSize)
                    }
                } else {
                    editor.handleDrag(startLocation: value.startLocation, currentLocation: value.location, phase: .changed, shiftHeld: shiftHeld)
                }
                editor.lastPanTranslation = value.translation
            }
            .onEnded { value in
                editor.stopEdgeScroll()
                if editor.currentTool == .page {
                    editor.commitPageMove()
                    editor.pageDragRawOrigin = nil
                } else if editor.currentTool == .select {
                    if editor.draggingBezierPointIndex != nil {
                        editor.endBezierPointDrag()
                    } else if editor.marqueeStart != nil {
                        editor.endMarquee()
                    } else if editor.hasSelection {
                        if let snapshot = editor.moveUndoSnapshot {
                            editor.commitMoveWithUndo(oldDocument: snapshot)
                            editor.moveUndoSnapshot = nil
                        }
                    }
                } else {
                    let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                    editor.handleDrag(startLocation: value.startLocation, currentLocation: value.location, phase: .ended, shiftHeld: shiftHeld)
                }
                editor.lastPanTranslation = nil
            }
    }
}
