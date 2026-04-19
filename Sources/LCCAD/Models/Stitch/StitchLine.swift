import Foundation
import CoreGraphics

enum StitchMode: String, Codable, Equatable, Sendable {
    case fixedPitch
    case variablePitch
}

struct StitchLine: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var sourceShapeId: UUID   // which shape this stitch line follows
    var ironId: UUID          // which pricking iron was used
    var mode: StitchMode
    var holes: [StitchHole]

    init(id: UUID = UUID(), sourceShapeId: UUID, ironId: UUID,
         mode: StitchMode = .fixedPitch, holes: [StitchHole] = []) {
        self.id = id
        self.sourceShapeId = sourceShapeId
        self.ironId = ironId
        self.mode = mode
        self.holes = holes
    }
}
