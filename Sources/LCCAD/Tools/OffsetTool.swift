import Foundation
import CoreGraphics

/// Creates a parallel copy of a line at a specified offset distance.
/// This is essential for generating stitch lines from edges (e.g., 3mm inset).
enum OffsetTool {
    /// Offset a line by a perpendicular distance.
    static func offsetLine(_ line: LineShape, distance: CGFloat) -> LineShape {
        let dx = line.endPoint.x - line.startPoint.x
        let dy = line.endPoint.y - line.startPoint.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return line }

        // Perpendicular unit vector (left side)
        let nx = -dy / length * distance
        let ny = dx / length * distance

        return LineShape(
            start: CGPoint(x: line.startPoint.x + nx, y: line.startPoint.y + ny),
            end: CGPoint(x: line.endPoint.x + nx, y: line.endPoint.y + ny),
            stroke: line.stroke
        )
    }

    /// Offset a rectangle inward or outward by a distance.
    static func offsetRectangle(_ rect: RectangleShape, distance: CGFloat) -> RectangleShape {
        let inset = distance
        return RectangleShape(
            origin: CGPoint(x: rect.origin.x + inset, y: rect.origin.y + inset),
            size: CGSize(width: max(0, rect.size.width - inset * 2), height: max(0, rect.size.height - inset * 2)),
            cornerRadius: max(0, rect.cornerRadius - inset),
            stroke: rect.stroke
        )
    }

    /// Offset an ellipse by changing radii.
    static func offsetEllipse(_ ellipse: EllipseShape, distance: CGFloat) -> EllipseShape {
        return EllipseShape(
            center: ellipse.center,
            radiusX: max(0, ellipse.radiusX - distance),
            radiusY: max(0, ellipse.radiusY - distance),
            stroke: ellipse.stroke
        )
    }
}
