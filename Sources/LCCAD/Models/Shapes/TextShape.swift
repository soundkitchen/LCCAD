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
    var stroke: StrokeStyle
    var isLocked: Bool = false

    init(id: UUID = UUID(), position: CGPoint, content: String = "Text", fontSize: CGFloat = 12, fontName: String = "Helvetica", isBold: Bool = false, isItalic: Bool = false, textAlignment: TextAlignment = .left, stroke: StrokeStyle = .default) {
        self.id = id
        self.position = position
        self.content = content
        self.fontSize = fontSize
        self.fontName = fontName
        self.isBold = isBold
        self.isItalic = isItalic
        self.textAlignment = textAlignment
        self.stroke = stroke
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

    var boundingBox: CGRect {
        let font = resolvedNSFont
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (content as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        ).size
        return CGRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let expanded = boundingBox.insetBy(dx: -tolerance, dy: -tolerance)
        return expanded.contains(point)
    }

    mutating func translate(by delta: CGPoint) {
        position = position + delta
    }
}
