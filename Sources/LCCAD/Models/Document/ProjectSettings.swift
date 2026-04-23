import Foundation
import CoreGraphics

// MARK: - Paper Size

enum PaperSize: String, Codable, Equatable, Sendable, CaseIterable {
    case a4, a3, b4, letter, legal, custom

    /// Paper dimensions in mm (portrait orientation).
    var dimensions: CGSize {
        switch self {
        case .a4:     return CGSize(width: 210, height: 297)
        case .a3:     return CGSize(width: 297, height: 420)
        case .b4:     return CGSize(width: 250, height: 353)
        case .letter: return CGSize(width: 215.9, height: 279.4)
        case .legal:  return CGSize(width: 215.9, height: 355.6)
        case .custom: return CGSize(width: 210, height: 297)
        }
    }

    var displayName: String {
        switch self {
        case .a4:     return "A4"
        case .a3:     return "A3"
        case .b4:     return "B4"
        case .letter: return "Letter"
        case .legal:  return "Legal"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Page Orientation

enum PageOrientation: String, Codable, Equatable, Sendable {
    case portrait, landscape
}

// MARK: - Print Page

struct PrintPage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var origin: CGPoint

    init(id: UUID = UUID(), origin: CGPoint = .zero) {
        self.id = id
        self.origin = origin
    }
}

// MARK: - Page Layout Settings

struct PageLayoutSettings: Codable, Equatable, Sendable {
    var pages: [PrintPage] = []
    var paperSize: PaperSize = .a4
    var customSize: CGSize? = nil
    var orientation: PageOrientation = .portrait
    var margin: CGFloat = 10.0
    var overlapMM: CGFloat = 10.0
    var showPageFrames: Bool = true

    /// Paper dimensions accounting for orientation.
    var effectivePageSize: CGSize {
        let base = paperSize == .custom ? (customSize ?? paperSize.dimensions) : paperSize.dimensions
        switch orientation {
        case .portrait:  return base
        case .landscape: return CGSize(width: base.height, height: base.width)
        }
    }

    /// Frame rectangle for a page in world coordinates (mm).
    func pageFrame(for page: PrintPage) -> CGRect {
        CGRect(origin: page.origin, size: effectivePageSize)
    }

    /// Printable area for a page (frame inset by margin).
    func pagePrintableArea(for page: PrintPage) -> CGRect {
        pageFrame(for: page).insetBy(dx: margin, dy: margin)
    }
}

// MARK: - Project Settings

struct ProjectSettings: Codable, Equatable, Sendable {
    var unit: LengthUnit = .millimeters
    var gridSpacing: CGFloat = 10.0
    var gridMajorInterval: Int = 5
    var snapToGrid: Bool = true
    var showGrid: Bool = true
    var showRuler: Bool = true
    var pageLayout: PageLayoutSettings = PageLayoutSettings()

    // Backward-compatible decoding: old files without pageLayout
    enum CodingKeys: String, CodingKey {
        case unit, gridSpacing, gridMajorInterval, snapToGrid, showGrid, showRuler, pageLayout
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unit = try container.decode(LengthUnit.self, forKey: .unit)
        gridSpacing = try container.decode(CGFloat.self, forKey: .gridSpacing)
        gridMajorInterval = try container.decode(Int.self, forKey: .gridMajorInterval)
        snapToGrid = try container.decode(Bool.self, forKey: .snapToGrid)
        showGrid = try container.decode(Bool.self, forKey: .showGrid)
        showRuler = try container.decodeIfPresent(Bool.self, forKey: .showRuler) ?? true
        pageLayout = try container.decodeIfPresent(PageLayoutSettings.self, forKey: .pageLayout)
            ?? PageLayoutSettings()
    }
}
