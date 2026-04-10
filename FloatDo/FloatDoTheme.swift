import SwiftUI

enum PanelMetrics {
    static let expandedSize = CGSize(width: 320, height: 420)
    static let collapsedSize = CGSize(width: 46, height: 108)
    static let cornerRadius: CGFloat = 26
    static let shadowRadius: CGFloat = 12
}

enum PanelMotion {
    static let stateAnimation = Animation.spring(response: 0.44, dampingFraction: 0.88, blendDuration: 0.18)
    static let frameAnimationDuration: TimeInterval = 0.42
    static let hoverExitDelay: TimeInterval = 0.12
    static let transitionDistance: CGFloat = 12
}

enum FloatDoTheme {
    static let shell = Color.black
    static let shellRaised = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let shellRaisedStrong = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let border = Color.white.opacity(0.1)
    static let divider = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.66)
    static let textTertiary = Color.white.opacity(0.38)
    static let iconMuted = Color.white.opacity(0.7)
    static let rowHover = Color.white.opacity(0.06)
    static let inputFill = Color.white.opacity(0.05)
    static let controlFill = Color.white.opacity(0.08)
    static let controlFillStrong = Color.white.opacity(0.14)
    static let success = Color(red: 0.42, green: 0.9, blue: 0.55)
    static let destructive = Color(red: 0.96, green: 0.4, blue: 0.4)
    static let warningBackground = Color(red: 0.2, green: 0.12, blue: 0.0)
    static let warningBorder = Color(red: 0.95, green: 0.65, blue: 0.2).opacity(0.4)
    static let warningText = Color(red: 1.0, green: 0.83, blue: 0.55)
    static let shadow = Color.black.opacity(0.45)
}
