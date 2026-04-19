import Foundation
import CoreGraphics

struct LineShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var startPoint: CGPoint
    var endPoint: CGPoint
    var stroke: StrokeStyle
    var isLocked: Bool = false

    init(id: UUID = UUID(), start: CGPoint, end: CGPoint, stroke: StrokeStyle = .default) {
        self.id = id
        self.startPoint = start
        self.endPoint = end
        self.stroke = stroke
    }

    var boundingBox: CGRect {
        CGRect(from: startPoint, to: endPoint)
    }

    var length: CGFloat {
        startPoint.distance(to: endPoint)
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let d = distanceFromPointToLineSegment(point: point, start: startPoint, end: endPoint)
        return d <= tolerance
    }

    mutating func translate(by delta: CGPoint) {
        startPoint = startPoint + delta
        endPoint = endPoint + delta
    }

    private func distanceFromPointToLineSegment(point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSq = dx * dx + dy * dy

        if lengthSq == 0 { return point.distance(to: start) }

        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSq
        t = max(0, min(1, t))

        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return point.distance(to: projection)
    }
}
