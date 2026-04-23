import SwiftUI

/// Persisted tunables for onboarding typography, chip padding, progress bar,
/// and step-advance spring. Card size and column layout are fixed.
final class ClassicOnboardingTweaks: ObservableObject, @unchecked Sendable {
    static let shared = ClassicOnboardingTweaks()

    enum Defaults {
        // MARK: Instruction chip
        static let chipHorizontalPadding: CGFloat = 44
        static let chipVerticalPadding: CGFloat = 44
        static let chipVerticalSpacing: CGFloat = 14

        // MARK: Typography
        static let interactiveTitleSize: CGFloat = 30
        static let interactiveBodySize: CGFloat = 15

        // MARK: Progress bar
        static let progressBarHeight: CGFloat = 6
        static let progressSpringResponse: CGFloat = 55 // * 0.01
        static let progressSpringDamping: CGFloat = 85  // * 0.01

        // MARK: Timings
        static let advanceSpringResponse: CGFloat = 45 // * 0.01
        static let advanceSpringDamping: CGFloat = 86  // * 0.01

        // MARK: Cursor (mock-local coordinates, points unless noted)
        static let cursorMoveDuration: CGFloat = 0.65
        static let cursorMoveSpringResponse: CGFloat = 55 // * 0.01
        static let cursorMoveSpringDamping: CGFloat = 82  // * 0.01
        static let cursorFadeDuration: CGFloat = 0.28
        /// Resting position — lower-left of the desktop mock, on the wallpaper.
        static let cursorRestingX: CGFloat = 130
        static let cursorRestingY: CGFloat = 470
        /// Inset inside the expanded panel rect for the input field target.
        /// X is from panel minX, aiming slightly left of center to hit the
        /// text field (submit button is on the right). Y is from panel maxY,
        /// offset upward to the vertical center of the input row.
        static let cursorInputFieldInsetX: CGFloat = 96
        static let cursorInputFieldInsetY: CGFloat = -24
        /// Inset inside the expanded panel rect for the first-row checkbox.
        /// X from panel minX, Y from panel minY. Header (~40pt) + list padding
        /// (4pt) + half row height (~18pt) ≈ 62pt to the checkbox center.
        static let cursorCheckboxInsetX: CGFloat = 22
        static let cursorCheckboxInsetY: CGFloat = 62
        /// Panel-edge hover hint (expanded panel). Slightly inside the left
        /// edge so the arrow tip sits just inside the glass.
        static let cursorPanelEdgeInsetX: CGFloat = 8
        static let cursorPanelEdgeInsetY: CGFloat = 0
    }

    private enum Keys {
        static let prefix = "floatlist.onboarding.tweak."

        static let chipHorizontalPadding = prefix + "chipHorizontalPadding"
        static let chipVerticalPadding = prefix + "chipVerticalPadding"
        static let chipVerticalSpacing = prefix + "chipVerticalSpacing"
        static let interactiveTitleSize = prefix + "interactiveTitleSize"
        static let interactiveBodySize = prefix + "interactiveBodySize"

        static let progressBarHeight = prefix + "progressBarHeight"
        static let progressSpringResponse = prefix + "progressSpringResponse"
        static let progressSpringDamping = prefix + "progressSpringDamping"

        static let advanceSpringResponse = prefix + "advanceSpringResponse"
        static let advanceSpringDamping = prefix + "advanceSpringDamping"

        static let cursorMoveDuration = prefix + "cursorMoveDuration"
        static let cursorMoveSpringResponse = prefix + "cursorMoveSpringResponse"
        static let cursorMoveSpringDamping = prefix + "cursorMoveSpringDamping"
        static let cursorFadeDuration = prefix + "cursorFadeDuration"
        static let cursorRestingX = prefix + "cursorRestingX"
        static let cursorRestingY = prefix + "cursorRestingY"
        static let cursorInputFieldInsetX = prefix + "cursorInputFieldInsetX"
        static let cursorInputFieldInsetY = prefix + "cursorInputFieldInsetY"
        static let cursorCheckboxInsetX = prefix + "cursorCheckboxInsetX"
        static let cursorCheckboxInsetY = prefix + "cursorCheckboxInsetY"
        static let cursorPanelEdgeInsetX = prefix + "cursorPanelEdgeInsetX"
        static let cursorPanelEdgeInsetY = prefix + "cursorPanelEdgeInsetY"
    }

    // MARK: Instruction chip
    @Published var chipHorizontalPadding: CGFloat { didSet { persist(chipHorizontalPadding, Keys.chipHorizontalPadding) } }
    @Published var chipVerticalPadding: CGFloat { didSet { persist(chipVerticalPadding, Keys.chipVerticalPadding) } }
    @Published var chipVerticalSpacing: CGFloat { didSet { persist(chipVerticalSpacing, Keys.chipVerticalSpacing) } }

    // MARK: Typography
    @Published var interactiveTitleSize: CGFloat { didSet { persist(interactiveTitleSize, Keys.interactiveTitleSize) } }
    @Published var interactiveBodySize: CGFloat { didSet { persist(interactiveBodySize, Keys.interactiveBodySize) } }

    // MARK: Progress bar
    @Published var progressBarHeight: CGFloat { didSet { persist(progressBarHeight, Keys.progressBarHeight) } }
    /// Stored ×100. Use `progressSpring`.
    @Published var progressSpringResponse: CGFloat { didSet { persist(progressSpringResponse, Keys.progressSpringResponse) } }
    @Published var progressSpringDamping: CGFloat { didSet { persist(progressSpringDamping, Keys.progressSpringDamping) } }

    // MARK: Timings
    /// Stored ×100. Use `advanceSpring`.
    @Published var advanceSpringResponse: CGFloat { didSet { persist(advanceSpringResponse, Keys.advanceSpringResponse) } }
    @Published var advanceSpringDamping: CGFloat { didSet { persist(advanceSpringDamping, Keys.advanceSpringDamping) } }

    // MARK: Cursor
    @Published var cursorMoveDuration: CGFloat { didSet { persist(cursorMoveDuration, Keys.cursorMoveDuration) } }
    /// Stored ×100. Consumers divide by 100 when building `.spring`.
    @Published var cursorMoveSpringResponseRaw: CGFloat { didSet { persist(cursorMoveSpringResponseRaw, Keys.cursorMoveSpringResponse) } }
    @Published var cursorMoveSpringDampingRaw: CGFloat { didSet { persist(cursorMoveSpringDampingRaw, Keys.cursorMoveSpringDamping) } }
    @Published var cursorFadeDuration: CGFloat { didSet { persist(cursorFadeDuration, Keys.cursorFadeDuration) } }
    @Published var cursorRestingX: CGFloat { didSet { persist(cursorRestingX, Keys.cursorRestingX) } }
    @Published var cursorRestingY: CGFloat { didSet { persist(cursorRestingY, Keys.cursorRestingY) } }
    @Published var cursorInputFieldInsetX: CGFloat { didSet { persist(cursorInputFieldInsetX, Keys.cursorInputFieldInsetX) } }
    @Published var cursorInputFieldInsetY: CGFloat { didSet { persist(cursorInputFieldInsetY, Keys.cursorInputFieldInsetY) } }
    @Published var cursorCheckboxInsetX: CGFloat { didSet { persist(cursorCheckboxInsetX, Keys.cursorCheckboxInsetX) } }
    @Published var cursorCheckboxInsetY: CGFloat { didSet { persist(cursorCheckboxInsetY, Keys.cursorCheckboxInsetY) } }
    @Published var cursorPanelEdgeInsetX: CGFloat { didSet { persist(cursorPanelEdgeInsetX, Keys.cursorPanelEdgeInsetX) } }
    @Published var cursorPanelEdgeInsetY: CGFloat { didSet { persist(cursorPanelEdgeInsetY, Keys.cursorPanelEdgeInsetY) } }

    var cursorMoveSpringResponse: Double { Double(cursorMoveSpringResponseRaw) / 100.0 }
    var cursorMoveSpringDamping: Double { Double(cursorMoveSpringDampingRaw) / 100.0 }

    // MARK: Derived helpers (decode scaled storage → real values)
    var progressSpring: Animation { .spring(response: Double(progressSpringResponse) / 100.0, dampingFraction: Double(progressSpringDamping) / 100.0) }
    var advanceSpring: Animation { .spring(response: Double(advanceSpringResponse) / 100.0, dampingFraction: Double(advanceSpringDamping) / 100.0) }

    private init() {
        let d = UserDefaults.standard
        chipHorizontalPadding = Self.read(Keys.chipHorizontalPadding, default: Defaults.chipHorizontalPadding, from: d)
        chipVerticalPadding = Self.read(Keys.chipVerticalPadding, default: Defaults.chipVerticalPadding, from: d)
        chipVerticalSpacing = Self.read(Keys.chipVerticalSpacing, default: Defaults.chipVerticalSpacing, from: d)
        interactiveTitleSize = Self.read(Keys.interactiveTitleSize, default: Defaults.interactiveTitleSize, from: d)
        interactiveBodySize = Self.read(Keys.interactiveBodySize, default: Defaults.interactiveBodySize, from: d)

        progressBarHeight = Self.read(Keys.progressBarHeight, default: Defaults.progressBarHeight, from: d)
        progressSpringResponse = Self.read(Keys.progressSpringResponse, default: Defaults.progressSpringResponse, from: d)
        progressSpringDamping = Self.read(Keys.progressSpringDamping, default: Defaults.progressSpringDamping, from: d)

        advanceSpringResponse = Self.read(Keys.advanceSpringResponse, default: Defaults.advanceSpringResponse, from: d)
        advanceSpringDamping = Self.read(Keys.advanceSpringDamping, default: Defaults.advanceSpringDamping, from: d)

        cursorMoveDuration = Self.read(Keys.cursorMoveDuration, default: Defaults.cursorMoveDuration, from: d)
        cursorMoveSpringResponseRaw = Self.read(Keys.cursorMoveSpringResponse, default: Defaults.cursorMoveSpringResponse, from: d)
        cursorMoveSpringDampingRaw = Self.read(Keys.cursorMoveSpringDamping, default: Defaults.cursorMoveSpringDamping, from: d)
        cursorFadeDuration = Self.read(Keys.cursorFadeDuration, default: Defaults.cursorFadeDuration, from: d)
        cursorRestingX = Self.read(Keys.cursorRestingX, default: Defaults.cursorRestingX, from: d)
        cursorRestingY = Self.read(Keys.cursorRestingY, default: Defaults.cursorRestingY, from: d)
        cursorInputFieldInsetX = Self.read(Keys.cursorInputFieldInsetX, default: Defaults.cursorInputFieldInsetX, from: d)
        cursorInputFieldInsetY = Self.read(Keys.cursorInputFieldInsetY, default: Defaults.cursorInputFieldInsetY, from: d)
        cursorCheckboxInsetX = Self.read(Keys.cursorCheckboxInsetX, default: Defaults.cursorCheckboxInsetX, from: d)
        cursorCheckboxInsetY = Self.read(Keys.cursorCheckboxInsetY, default: Defaults.cursorCheckboxInsetY, from: d)
        cursorPanelEdgeInsetX = Self.read(Keys.cursorPanelEdgeInsetX, default: Defaults.cursorPanelEdgeInsetX, from: d)
        cursorPanelEdgeInsetY = Self.read(Keys.cursorPanelEdgeInsetY, default: Defaults.cursorPanelEdgeInsetY, from: d)
    }

    func resetToDefaults() {
        chipHorizontalPadding = Defaults.chipHorizontalPadding
        chipVerticalPadding = Defaults.chipVerticalPadding
        chipVerticalSpacing = Defaults.chipVerticalSpacing
        interactiveTitleSize = Defaults.interactiveTitleSize
        interactiveBodySize = Defaults.interactiveBodySize

        progressBarHeight = Defaults.progressBarHeight
        progressSpringResponse = Defaults.progressSpringResponse
        progressSpringDamping = Defaults.progressSpringDamping

        advanceSpringResponse = Defaults.advanceSpringResponse
        advanceSpringDamping = Defaults.advanceSpringDamping

        cursorMoveDuration = Defaults.cursorMoveDuration
        cursorMoveSpringResponseRaw = Defaults.cursorMoveSpringResponse
        cursorMoveSpringDampingRaw = Defaults.cursorMoveSpringDamping
        cursorFadeDuration = Defaults.cursorFadeDuration
        cursorRestingX = Defaults.cursorRestingX
        cursorRestingY = Defaults.cursorRestingY
        cursorInputFieldInsetX = Defaults.cursorInputFieldInsetX
        cursorInputFieldInsetY = Defaults.cursorInputFieldInsetY
        cursorCheckboxInsetX = Defaults.cursorCheckboxInsetX
        cursorCheckboxInsetY = Defaults.cursorCheckboxInsetY
        cursorPanelEdgeInsetX = Defaults.cursorPanelEdgeInsetX
        cursorPanelEdgeInsetY = Defaults.cursorPanelEdgeInsetY
    }

    private static func read(_ key: String, default fallback: CGFloat, from defaults: UserDefaults) -> CGFloat {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return CGFloat(defaults.double(forKey: key))
    }

    private func persist(_ value: CGFloat, _ key: String) {
        UserDefaults.standard.set(Double(value), forKey: key)
    }
}
