import SwiftUI
import AppKit

extension Color {
    /// Explicit page background for scrollable content panes, independent of system
    /// window-background colors — those shifted to near-white under Liquid Glass,
    /// which is what made controlBackgroundColor cards blend into the page.
    static let appPageBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.14, alpha: 1)
            : NSColor(white: 0.93, alpha: 1)
    })

    /// Explicit card surface color, paired with appPageBackground for contrast.
    static let appCardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.20, alpha: 1)
            : NSColor.white
    })
}
