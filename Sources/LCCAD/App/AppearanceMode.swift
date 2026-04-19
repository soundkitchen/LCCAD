import SwiftUI
import AppKit

/// User preference for color mode: system default, forced light, or forced dark.
enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    /// The NSAppearance to apply, or nil for system default.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Apply this mode to the entire application immediately.
    func apply() {
        NSApp.appearance = nsAppearance
    }
}
