import Foundation
import CoreGraphics

struct CanvasTransform: Sendable {
    var offset: CGPoint = .zero   // pan offset in screen pixels
    var scale: CGFloat = 3.0      // zoom level (pixels per mm, ~1mm = 3px at default)

    /// Convert world coordinates (mm) to screen coordinates (pixels)
    func worldToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + offset.x,
            y: point.y * scale + offset.y
        )
    }

    /// Convert screen coordinates (pixels) to world coordinates (mm)
    func screenToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - offset.x) / scale,
            y: (point.y - offset.y) / scale
        )
    }

    /// Convert a world-space distance to screen-space
    func worldToScreenDistance(_ distance: CGFloat) -> CGFloat {
        distance * scale
    }

    /// Convert a screen-space distance to world-space
    func screenToWorldDistance(_ distance: CGFloat) -> CGFloat {
        distance / scale
    }

    /// Convert a world-space rect to screen-space
    func worldToScreen(_ rect: CGRect) -> CGRect {
        let origin = worldToScreen(rect.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// Zoom towards a specific screen point
    mutating func zoom(by factor: CGFloat, center: CGPoint) {
        let worldCenter = screenToWorld(center)
        scale *= factor
        scale = max(0.5, min(50, scale))  // clamp zoom
        offset.x = center.x - worldCenter.x * scale
        offset.y = center.y - worldCenter.y * scale
    }

    /// Pan by a delta in screen pixels
    mutating func pan(by delta: CGPoint) {
        offset.x += delta.x
        offset.y += delta.y
    }

    var zoomPercentage: Int {
        Int(round(scale / 3.0 * 100))
    }
}
