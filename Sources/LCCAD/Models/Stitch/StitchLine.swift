import Foundation
import CoreGraphics

enum StitchMode: String, Codable, Equatable, Sendable, CaseIterable {
    case fixedPitch
    case variablePitch
    /// Exactly N holes spread evenly over the whole run, ignoring the iron pitch.
    /// The count lives in `StitchLine.holeCount` (#23b).
    case evenCount
    /// Exact pitch from the run start up to a user-picked point, then the leftover
    /// stretch is evened so the last hole lands on the run end. The picked point
    /// lives in `StitchLine.fixedLength` (#23c).
    case hybrid

    /// Human-readable label for the stitch mode picker.
    var displayName: String {
        switch self {
        case .fixedPitch: return "Fixed Pitch"
        case .variablePitch: return "Variable Pitch"
        case .evenCount: return "Even Count"
        case .hybrid: return "Hybrid"
        }
    }
}

struct StitchLine: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// Shapes this stitch line follows. A simple line follows one shape; a welded
    /// outline (several connected segments stitched as one run) follows several, in
    /// path order.
    var sourceShapeIds: [UUID]
    var ironId: UUID          // which pricking iron was used
    var mode: StitchMode
    /// Requested hole count for `.evenCount` mode; nil for pitch-driven modes.
    /// Persisted so shape edits regenerate the run with the same count.
    var holeCount: Int?
    /// Arc-length (mm from the run start) where `.hybrid` hands over from fixed pitch
    /// to evened spacing; nil for the other modes. Persisted so shape edits regenerate
    /// the run with the same split point.
    var fixedLength: CGFloat?
    var holes: [StitchHole]

    init(id: UUID = UUID(), sourceShapeIds: [UUID], ironId: UUID,
         mode: StitchMode = .fixedPitch, holeCount: Int? = nil,
         fixedLength: CGFloat? = nil, holes: [StitchHole] = []) {
        self.id = id
        self.sourceShapeIds = sourceShapeIds
        self.ironId = ironId
        self.mode = mode
        self.holeCount = holeCount
        self.fixedLength = fixedLength
        self.holes = holes
    }

    /// Convenience for the common single-shape case.
    init(id: UUID = UUID(), sourceShapeId: UUID, ironId: UUID,
         mode: StitchMode = .fixedPitch, holeCount: Int? = nil,
         fixedLength: CGFloat? = nil, holes: [StitchHole] = []) {
        self.init(id: id, sourceShapeIds: [sourceShapeId], ironId: ironId,
                  mode: mode, holeCount: holeCount, fixedLength: fixedLength, holes: holes)
    }

    // Codable with backward compatibility: documents written before welded stitch
    // lines stored a single `sourceShapeId`; decode it into the array when present.
    enum CodingKeys: String, CodingKey {
        case id, sourceShapeId, sourceShapeIds, ironId, mode, holeCount, fixedLength, holes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        if let ids = try c.decodeIfPresent([UUID].self, forKey: .sourceShapeIds) {
            sourceShapeIds = ids
        } else if let single = try c.decodeIfPresent(UUID.self, forKey: .sourceShapeId) {
            sourceShapeIds = [single]
        } else {
            sourceShapeIds = []
        }
        ironId = try c.decode(UUID.self, forKey: .ironId)
        mode = try c.decodeIfPresent(StitchMode.self, forKey: .mode) ?? .fixedPitch
        holeCount = try c.decodeIfPresent(Int.self, forKey: .holeCount)
        fixedLength = try c.decodeIfPresent(CGFloat.self, forKey: .fixedLength)
        holes = try c.decodeIfPresent([StitchHole].self, forKey: .holes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourceShapeIds, forKey: .sourceShapeIds)
        try c.encode(ironId, forKey: .ironId)
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(holeCount, forKey: .holeCount)
        try c.encodeIfPresent(fixedLength, forKey: .fixedLength)
        try c.encode(holes, forKey: .holes)
    }
}
