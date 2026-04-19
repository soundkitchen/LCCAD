import SwiftUI

/// Design tokens matching the Pencil design file (lccad.pen) variables.
/// These adapt to Light / Dark mode via @Environment(\.colorScheme).
enum DesignTokens {
    // MARK: - Backgrounds

    static func bgApp(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1E1E1E) : Color(hex: 0xF5F5F5)
    }
    static func bgPanel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x252526) : Color(hex: 0xFFFFFF)
    }
    static func bgToolbar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2D2D2D) : Color(hex: 0xF8F8F8)
    }
    static func bgCanvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1E1E1E) : Color(hex: 0xF0F0F0)
    }
    static func bgStatusbar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x007ACC) : Color(hex: 0xE8E8E8)
    }
    static func bgInput(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x3C3C3C) : Color(hex: 0xFFFFFF)
    }
    static func bgToolActive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x404040) : Color(hex: 0xE0E0E0)
    }
    static func bgSection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2A2A2A) : Color(hex: 0xF0F0F0)
    }

    // MARK: - Borders

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x3D3D3D) : Color(hex: 0xD9D9D9)
    }
    static func borderLight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x333333) : Color(hex: 0xEBEBEB)
    }

    // MARK: - Text

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xE0E0E0) : Color(hex: 0x1A1A1A)
    }
    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x999999) : Color(hex: 0x666666)
    }
    static func textMuted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x666666) : Color(hex: 0x999999)
    }

    // MARK: - Icons

    static func iconPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xCCCCCC) : Color(hex: 0x444444)
    }
    static func iconSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x777777) : Color(hex: 0x888888)
    }

    // MARK: - Grid

    static func gridLine(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x404040) : Color(hex: 0xB0B0B0)
    }
    static func gridLineMajor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x444444) : Color(hex: 0xA8A8A8)
    }

    // MARK: - Pattern

    static func patternStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xCCCCCC) : Color(hex: 0x333333)
    }

    // MARK: - Menu Bar

    static func bgMenubar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x333333) : Color(hex: 0xEFEFEF)
    }

    // MARK: - Accent

    static let accent = Color(hex: 0x4A90D9)
    static let accentHover = Color(hex: 0x3A7BC8)
    static let stitchColor = Color(hex: 0xD4A574)
    static let textOnAccent = Color.white
}

// MARK: - Color hex init

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
