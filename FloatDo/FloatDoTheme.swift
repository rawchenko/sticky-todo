import SwiftUI
import AppKit

enum PanelMetrics {
    static let expandedSize = CGSize(width: 360, height: 580)
    static let collapsedSize = CGSize(width: 46, height: 108)
    static let cornerRadius: CGFloat = 32
    static let shadowRadius: CGFloat = 24
    static let edgeInset: CGFloat = 8
}

enum RowMetrics {
    /// Fallback row height used during drag-reorder hit-testing before
    /// `RowHeightPreferenceKey` reports a measured height for a given row.
    static let estimatedHeight: CGFloat = 40
}

enum ListPillMetrics {
    /// Fallback pill width used during drag-reorder hit-testing before
    /// `ListWidthPreferenceKey` reports a measured width for a given pill.
    static let estimatedWidth: CGFloat = 44
}

enum PanelMotion {
    static let stateAnimation = Animation.spring(response: 0.44, dampingFraction: 0.88, blendDuration: 0.18)
    static let frameAnimationDuration: TimeInterval = 0.42
    static let hoverExitDelay: TimeInterval = 0.12
    static let transitionDistance: CGFloat = 12
}

extension Color {
    /// Dynamic color that resolves against the current `NSAppearance` so the
    /// panel tracks the system light/dark setting automatically.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            switch match {
            case .darkAqua, .vibrantDark:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
    }
}

/// Adaptive palette tuned for both light and dark Liquid Glass shells.
enum FloatDoTheme {
    // Shell tint — native Liquid Glass adapts on its own; we only bias slightly.
    static let shellTint = Color.dynamic(
        light: Color.white.opacity(0.08),
        dark: Color.white.opacity(0.05)
    )
    static let shellFallback = Color.dynamic(
        light: Color.white.opacity(0.82),
        dark: Color.black.opacity(0.55)
    )

    // Text
    static let textPrimary = Color.dynamic(
        light: Color(white: 0.08),
        dark: Color(white: 0.96)
    )
    static let textSecondary = Color.dynamic(
        light: Color(white: 0.08).opacity(0.55),
        dark: Color(white: 0.96).opacity(0.62)
    )
    static let textTertiary = Color.dynamic(
        light: Color(white: 0.08).opacity(0.35),
        dark: Color(white: 0.96).opacity(0.42)
    )

    // Icons
    static let iconMuted = Color.dynamic(
        light: Color(white: 0.08).opacity(0.62),
        dark: Color(white: 0.96).opacity(0.70)
    )

    // Surfaces
    static let rowHover = Color.dynamic(
        light: Color.black.opacity(0.05),
        dark: Color.white.opacity(0.08)
    )
    static let inputFill = Color.dynamic(
        light: Color.black.opacity(0.04),
        dark: Color.white.opacity(0.07)
    )
    static let controlFill = Color.dynamic(
        light: Color.black.opacity(0.06),
        dark: Color.white.opacity(0.10)
    )
    static let controlFillStrong = Color.dynamic(
        light: Color.black.opacity(0.10),
        dark: Color.white.opacity(0.16)
    )
    static let tabActiveFill = Color.dynamic(
        light: Color.black.opacity(0.06),
        dark: Color.white.opacity(0.10)
    )

    // Strokes / borders that read against the panel content
    static let hairline = Color.dynamic(
        light: Color.black.opacity(0.12),
        dark: Color.white.opacity(0.18)
    )

    // Prominent chip fill used as the pre-macOS 26 Liquid Glass fallback.
    static let prominentChipFill = Color.dynamic(
        light: Color.white.opacity(0.85),
        dark: Color.white.opacity(0.92)
    )

    // Status
    static let success = Color(red: 0.24, green: 0.74, blue: 0.38)
    static let destructive = Color(red: 0.87, green: 0.30, blue: 0.30)

    // Legacy bits that still get consumed elsewhere
    static let warningBackground = Color.dynamic(
        light: Color(red: 1.0, green: 0.92, blue: 0.78),
        dark: Color(red: 0.32, green: 0.22, blue: 0.08)
    )
    static let warningBorder = Color.dynamic(
        light: Color(red: 0.95, green: 0.65, blue: 0.20).opacity(0.50),
        dark: Color(red: 0.98, green: 0.72, blue: 0.28).opacity(0.55)
    )
    static let warningText = Color.dynamic(
        light: Color(red: 0.55, green: 0.35, blue: 0.05),
        dark: Color(red: 1.0, green: 0.86, blue: 0.55)
    )
    static let shadow = Color.black.opacity(0.28)

    /// Panel drop-shadow color. Honors the user-set opacity, but attenuates in
    /// dark mode so the shadow doesn't read as a heavy black halo on dark
    /// desktops.
    static func panelShadow(opacity: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            let isDark = (match == .darkAqua || match == .vibrantDark)
            let alpha = isDark ? opacity * 0.55 : opacity
            return NSColor(white: 0, alpha: CGFloat(alpha))
        })
    }
}
