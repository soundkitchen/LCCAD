import Foundation
import CoreGraphics

struct ProjectSettings: Codable, Equatable, Sendable {
    var unit: LengthUnit = .millimeters
    var gridSpacing: CGFloat = 10.0
    var gridMajorInterval: Int = 5
    var snapToGrid: Bool = true
    var showGrid: Bool = true
    var showRuler: Bool = true
}
