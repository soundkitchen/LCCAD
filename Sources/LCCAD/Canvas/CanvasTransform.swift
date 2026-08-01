import Foundation
import CoreGraphics

struct CanvasTransform: Sendable {
    /// ズーム下限・上限（pt/mm）。全ズーム経路で共通のクランプ範囲 (#60)
    static let minScale: CGFloat = 0.5
    static let maxScale: CGFloat = 50

    /// ディスプレイの物理密度が判明するまでの暫定基準（1mm = 3pt、#62 以前の固定値）
    static let fallbackBaselineScale: CGFloat = 3.0

    var offset: CGPoint = .zero   // pan offset in screen points
    var scale: CGFloat = CanvasTransform.fallbackBaselineScale  // zoom level (points per mm)

    /// 100% と定義する scale 値（pt/mm）。ウィンドウのあるディスプレイの
    /// 物理解像度から算出され、「100% = 画面上の 1mm が実物の 1mm」を意味する (#62)。
    /// ディスプレイ未判明時は fallbackBaselineScale
    var baselineScale: CGFloat = CanvasTransform.fallbackBaselineScale

    /// scale をズーム範囲 [minScale, maxScale] に収める
    static func clampScale(_ value: CGFloat) -> CGFloat {
        max(minScale, min(maxScale, value))
    }

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
        scale = CanvasTransform.clampScale(scale * factor)
        offset.x = center.x - worldCenter.x * scale
        offset.y = center.y - worldCenter.y * scale
    }

    /// Pan by a delta in screen pixels
    mutating func pan(by delta: CGPoint) {
        offset.x += delta.x
        offset.y += delta.y
    }

    var zoomPercentage: Int {
        Int(round(scale / baselineScale * 100))
    }
}
