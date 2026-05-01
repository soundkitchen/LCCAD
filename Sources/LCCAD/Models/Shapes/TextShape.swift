import Foundation
import CoreGraphics
import AppKit

enum TextAlignment: String, Codable, Equatable, Sendable, CaseIterable {
    case left
    case center
    case right
}

struct TextShape: Shape, Codable, Equatable, Sendable {
    let id: UUID
    var position: CGPoint
    var content: String
    var fontSize: CGFloat
    var fontName: String
    var isBold: Bool
    var isItalic: Bool
    var textAlignment: TextAlignment
    var rotation: CGFloat = 0  // radians, applied around the unrotated center
    var stroke: StrokeStyle
    var isLocked: Bool = false

    init(id: UUID = UUID(), position: CGPoint, content: String = "Text", fontSize: CGFloat = 12, fontName: String = "Helvetica", isBold: Bool = false, isItalic: Bool = false, textAlignment: TextAlignment = .left, rotation: CGFloat = 0, stroke: StrokeStyle = .default) {
        self.id = id
        self.position = position
        self.content = content
        self.fontSize = fontSize
        self.fontName = fontName
        self.isBold = isBold
        self.isItalic = isItalic
        self.textAlignment = textAlignment
        self.rotation = rotation
        self.stroke = stroke
    }

    enum CodingKeys: String, CodingKey {
        case id, position, content, fontSize, fontName, isBold, isItalic, textAlignment, rotation, stroke, isLocked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        position = try c.decode(CGPoint.self, forKey: .position)
        content = try c.decode(String.self, forKey: .content)
        fontSize = try c.decode(CGFloat.self, forKey: .fontSize)
        fontName = try c.decode(String.self, forKey: .fontName)
        isBold = try c.decode(Bool.self, forKey: .isBold)
        isItalic = try c.decode(Bool.self, forKey: .isItalic)
        textAlignment = try c.decode(TextAlignment.self, forKey: .textAlignment)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        stroke = try c.decode(StrokeStyle.self, forKey: .stroke)
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }

    /// Resolve the NSFont with bold/italic traits applied
    var resolvedNSFont: NSFont {
        let baseFont = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        var traits: NSFontTraitMask = []
        if isBold { traits.insert(.boldFontMask) }
        if isItalic { traits.insert(.italicFontMask) }
        if traits.isEmpty { return baseFont }
        return NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
    }

    /// Size of the text glyphs in world units, ignoring rotation.
    var unrotatedSize: CGSize {
        let font = resolvedNSFont
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (content as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        ).size
    }

    /// Center of the unrotated text bbox. Rotation pivots around this point.
    var unrotatedCenter: CGPoint {
        let s = unrotatedSize
        return CGPoint(x: position.x + s.width / 2, y: position.y + s.height / 2)
    }

    var boundingBox: CGRect {
        let s = unrotatedSize
        let unrotated = CGRect(x: position.x, y: position.y, width: s.width, height: s.height)
        guard rotation != 0 else { return unrotated }
        let c = unrotatedCenter
        let corners = [
            unrotated.origin,
            CGPoint(x: unrotated.maxX, y: unrotated.minY),
            CGPoint(x: unrotated.maxX, y: unrotated.maxY),
            CGPoint(x: unrotated.minX, y: unrotated.maxY),
        ].map { $0.rotated(around: c, angle: rotation) }
        var minX = corners[0].x, minY = corners[0].y
        var maxX = corners[0].x, maxY = corners[0].y
        for p in corners.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let testPoint = rotation == 0
            ? point
            : point.rotated(around: unrotatedCenter, angle: -rotation)
        let s = unrotatedSize
        let rect = CGRect(x: position.x, y: position.y, width: s.width, height: s.height)
        return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(testPoint)
    }

    mutating func translate(by delta: CGPoint) {
        position = position + delta
    }

    mutating func mirror(axis: MirrorAxis) {
        position = position.mirrored(across: axis)
        rotation = -rotation
    }

    mutating func rotate(around pivot: CGPoint, angle: CGFloat) {
        let oldCenter = unrotatedCenter
        let newCenter = oldCenter.rotated(around: pivot, angle: angle)
        let s = unrotatedSize
        position = CGPoint(x: newCenter.x - s.width / 2, y: newCenter.y - s.height / 2)
        rotation += angle
    }
}
