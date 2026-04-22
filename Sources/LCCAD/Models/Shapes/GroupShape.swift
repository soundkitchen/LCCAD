import Foundation
import CoreGraphics

struct GroupShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var children: [AnyShape]
    var isLocked: Bool = false

    var stroke: StrokeStyle {
        get { children.first?.stroke ?? .default }
        set {
            for i in children.indices {
                children[i].stroke = newValue
            }
        }
    }

    init(id: UUID = UUID(), children: [AnyShape]) {
        self.id = id
        self.children = children
    }

    var boundingBox: CGRect {
        guard let first = children.first else { return .zero }
        return children.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        children.contains { $0.hitTest(point: point, tolerance: tolerance) }
    }

    mutating func translate(by delta: CGPoint) {
        for i in children.indices {
            children[i].translate(by: delta)
        }
    }
}
