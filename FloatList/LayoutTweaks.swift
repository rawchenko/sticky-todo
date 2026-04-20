import SwiftUI

/// Runtime-adjustable layout values. Settings → Layout binds sliders to these
/// published properties; `PanelManager` and `ContentView` read them live so
/// changes apply without relaunching the app.
///
/// Not @MainActor — views read these from any actor, and mutations flow
/// through SwiftUI bindings which are already on the main thread.
final class LayoutTweaks: ObservableObject, @unchecked Sendable {
    static let shared = LayoutTweaks()

    enum Defaults {
        static let panelCornerRadius: CGFloat = 18
        static let handleCornerRadius: CGFloat = 18
        static let collapsedWidth: CGFloat = 48
        static let collapsedHeight: CGFloat = 48
        static let expandedWidth: CGFloat = 280
        static let expandedHeight: CGFloat = 440
        static let edgeInset: CGFloat = 2

        static let contentHorizontalPadding: CGFloat = 4
        static let contentTopPadding: CGFloat = 4
        static let contentBottomPadding: CGFloat = 0
        static let rowSpacing: CGFloat = 4

        static let inputCornerRadius: CGFloat = 12
        static let inputLeadingPadding: CGFloat = 12
        static let inputTrailingPadding: CGFloat = 6
        static let inputVerticalPadding: CGFloat = 6

        static let rowCornerRadius: CGFloat = 12
        static let rowHorizontalPadding: CGFloat = 8
        static let rowVerticalPadding: CGFloat = 8
        static let rowInnerSpacing: CGFloat = 8

        static let bodyTextSize: CGFloat = 14
        static let secondaryTextSize: CGFloat = 12
        static let checkboxSize: CGFloat = 18
        static let actionIconSize: CGFloat = 12
        static let listIconSize: CGFloat = 14

        static let pillCornerRadius: CGFloat = 12
        static let pillHorizontalPadding: CGFloat = 8
        static let pillVerticalPadding: CGFloat = 8
        static let pillSpacing: CGFloat = 4

        static let checkmarkSize: CGFloat = 10
        static let addListIconSize: CGFloat = 12
    }

    private enum Keys {
        static let panelCornerRadius = "floatlist.layout.panelCornerRadius"
        static let handleCornerRadius = "floatlist.layout.handleCornerRadius"
        static let collapsedWidth = "floatlist.layout.collapsedWidth"
        static let collapsedHeight = "floatlist.layout.collapsedHeight"
        static let expandedWidth = "floatlist.layout.expandedWidth"
        static let expandedHeight = "floatlist.layout.expandedHeight"
        static let edgeInset = "floatlist.layout.edgeInset"

        static let contentHorizontalPadding = "floatlist.layout.contentHorizontalPadding"
        static let contentTopPadding = "floatlist.layout.contentTopPadding"
        static let contentBottomPadding = "floatlist.layout.contentBottomPadding"
        static let rowSpacing = "floatlist.layout.rowSpacing"

        static let inputCornerRadius = "floatlist.layout.inputCornerRadius"
        static let inputLeadingPadding = "floatlist.layout.inputLeadingPadding"
        static let inputTrailingPadding = "floatlist.layout.inputTrailingPadding"
        static let inputVerticalPadding = "floatlist.layout.inputVerticalPadding"

        static let rowCornerRadius = "floatlist.layout.rowCornerRadius"
        static let rowHorizontalPadding = "floatlist.layout.rowHorizontalPadding"
        static let rowVerticalPadding = "floatlist.layout.rowVerticalPadding"
        static let rowInnerSpacing = "floatlist.layout.rowInnerSpacing"

        static let bodyTextSize = "floatlist.layout.bodyTextSize"
        static let secondaryTextSize = "floatlist.layout.secondaryTextSize"
        static let checkboxSize = "floatlist.layout.checkboxSize"
        static let actionIconSize = "floatlist.layout.actionIconSize"
        static let listIconSize = "floatlist.layout.listIconSize"

        static let pillCornerRadius = "floatlist.layout.pillCornerRadius"
        static let pillHorizontalPadding = "floatlist.layout.pillHorizontalPadding"
        static let pillVerticalPadding = "floatlist.layout.pillVerticalPadding"
        static let pillSpacing = "floatlist.layout.pillSpacing"

        static let checkmarkSize = "floatlist.layout.checkmarkSize"
        static let addListIconSize = "floatlist.layout.addListIconSize"
    }

    @Published var panelCornerRadius: CGFloat { didSet { persist(panelCornerRadius, Keys.panelCornerRadius) } }
    @Published var handleCornerRadius: CGFloat { didSet { persist(handleCornerRadius, Keys.handleCornerRadius) } }
    @Published var collapsedWidth: CGFloat { didSet { persist(collapsedWidth, Keys.collapsedWidth) } }
    @Published var collapsedHeight: CGFloat { didSet { persist(collapsedHeight, Keys.collapsedHeight) } }
    @Published var expandedWidth: CGFloat { didSet { persist(expandedWidth, Keys.expandedWidth) } }
    @Published var expandedHeight: CGFloat { didSet { persist(expandedHeight, Keys.expandedHeight) } }
    @Published var edgeInset: CGFloat { didSet { persist(edgeInset, Keys.edgeInset) } }

    @Published var contentHorizontalPadding: CGFloat { didSet { persist(contentHorizontalPadding, Keys.contentHorizontalPadding) } }
    @Published var contentTopPadding: CGFloat { didSet { persist(contentTopPadding, Keys.contentTopPadding) } }
    @Published var contentBottomPadding: CGFloat { didSet { persist(contentBottomPadding, Keys.contentBottomPadding) } }
    @Published var rowSpacing: CGFloat { didSet { persist(rowSpacing, Keys.rowSpacing) } }

    @Published var inputCornerRadius: CGFloat { didSet { persist(inputCornerRadius, Keys.inputCornerRadius) } }
    @Published var inputLeadingPadding: CGFloat { didSet { persist(inputLeadingPadding, Keys.inputLeadingPadding) } }
    @Published var inputTrailingPadding: CGFloat { didSet { persist(inputTrailingPadding, Keys.inputTrailingPadding) } }
    @Published var inputVerticalPadding: CGFloat { didSet { persist(inputVerticalPadding, Keys.inputVerticalPadding) } }

    @Published var rowCornerRadius: CGFloat { didSet { persist(rowCornerRadius, Keys.rowCornerRadius) } }
    @Published var rowHorizontalPadding: CGFloat { didSet { persist(rowHorizontalPadding, Keys.rowHorizontalPadding) } }
    @Published var rowVerticalPadding: CGFloat { didSet { persist(rowVerticalPadding, Keys.rowVerticalPadding) } }
    @Published var rowInnerSpacing: CGFloat { didSet { persist(rowInnerSpacing, Keys.rowInnerSpacing) } }

    @Published var bodyTextSize: CGFloat { didSet { persist(bodyTextSize, Keys.bodyTextSize) } }
    @Published var secondaryTextSize: CGFloat { didSet { persist(secondaryTextSize, Keys.secondaryTextSize) } }
    @Published var checkboxSize: CGFloat { didSet { persist(checkboxSize, Keys.checkboxSize) } }
    @Published var actionIconSize: CGFloat { didSet { persist(actionIconSize, Keys.actionIconSize) } }
    @Published var listIconSize: CGFloat { didSet { persist(listIconSize, Keys.listIconSize) } }

    @Published var pillCornerRadius: CGFloat { didSet { persist(pillCornerRadius, Keys.pillCornerRadius) } }
    @Published var pillHorizontalPadding: CGFloat { didSet { persist(pillHorizontalPadding, Keys.pillHorizontalPadding) } }
    @Published var pillVerticalPadding: CGFloat { didSet { persist(pillVerticalPadding, Keys.pillVerticalPadding) } }
    @Published var pillSpacing: CGFloat { didSet { persist(pillSpacing, Keys.pillSpacing) } }

    @Published var checkmarkSize: CGFloat { didSet { persist(checkmarkSize, Keys.checkmarkSize) } }
    @Published var addListIconSize: CGFloat { didSet { persist(addListIconSize, Keys.addListIconSize) } }

    var expandedSize: CGSize { CGSize(width: expandedWidth, height: expandedHeight) }
    var collapsedSize: CGSize { CGSize(width: collapsedWidth, height: collapsedHeight) }

    private init() {
        let d = UserDefaults.standard
        panelCornerRadius = Self.read(Keys.panelCornerRadius, default: Defaults.panelCornerRadius, from: d)
        handleCornerRadius = Self.read(Keys.handleCornerRadius, default: Defaults.handleCornerRadius, from: d)
        collapsedWidth = Self.read(Keys.collapsedWidth, default: Defaults.collapsedWidth, from: d)
        collapsedHeight = Self.read(Keys.collapsedHeight, default: Defaults.collapsedHeight, from: d)
        expandedWidth = Self.read(Keys.expandedWidth, default: Defaults.expandedWidth, from: d)
        expandedHeight = Self.read(Keys.expandedHeight, default: Defaults.expandedHeight, from: d)
        edgeInset = Self.read(Keys.edgeInset, default: Defaults.edgeInset, from: d)

        contentHorizontalPadding = Self.read(Keys.contentHorizontalPadding, default: Defaults.contentHorizontalPadding, from: d)
        contentTopPadding = Self.read(Keys.contentTopPadding, default: Defaults.contentTopPadding, from: d)
        contentBottomPadding = Self.read(Keys.contentBottomPadding, default: Defaults.contentBottomPadding, from: d)
        rowSpacing = Self.read(Keys.rowSpacing, default: Defaults.rowSpacing, from: d)

        inputCornerRadius = Self.read(Keys.inputCornerRadius, default: Defaults.inputCornerRadius, from: d)
        inputLeadingPadding = Self.read(Keys.inputLeadingPadding, default: Defaults.inputLeadingPadding, from: d)
        inputTrailingPadding = Self.read(Keys.inputTrailingPadding, default: Defaults.inputTrailingPadding, from: d)
        inputVerticalPadding = Self.read(Keys.inputVerticalPadding, default: Defaults.inputVerticalPadding, from: d)

        rowCornerRadius = Self.read(Keys.rowCornerRadius, default: Defaults.rowCornerRadius, from: d)
        rowHorizontalPadding = Self.read(Keys.rowHorizontalPadding, default: Defaults.rowHorizontalPadding, from: d)
        rowVerticalPadding = Self.read(Keys.rowVerticalPadding, default: Defaults.rowVerticalPadding, from: d)
        rowInnerSpacing = Self.read(Keys.rowInnerSpacing, default: Defaults.rowInnerSpacing, from: d)

        bodyTextSize = Self.read(Keys.bodyTextSize, default: Defaults.bodyTextSize, from: d)
        secondaryTextSize = Self.read(Keys.secondaryTextSize, default: Defaults.secondaryTextSize, from: d)
        checkboxSize = Self.read(Keys.checkboxSize, default: Defaults.checkboxSize, from: d)
        actionIconSize = Self.read(Keys.actionIconSize, default: Defaults.actionIconSize, from: d)
        listIconSize = Self.read(Keys.listIconSize, default: Defaults.listIconSize, from: d)

        pillCornerRadius = Self.read(Keys.pillCornerRadius, default: Defaults.pillCornerRadius, from: d)
        pillHorizontalPadding = Self.read(Keys.pillHorizontalPadding, default: Defaults.pillHorizontalPadding, from: d)
        pillVerticalPadding = Self.read(Keys.pillVerticalPadding, default: Defaults.pillVerticalPadding, from: d)
        pillSpacing = Self.read(Keys.pillSpacing, default: Defaults.pillSpacing, from: d)

        checkmarkSize = Self.read(Keys.checkmarkSize, default: Defaults.checkmarkSize, from: d)
        addListIconSize = Self.read(Keys.addListIconSize, default: Defaults.addListIconSize, from: d)
    }

    func resetToDefaults() {
        panelCornerRadius = Defaults.panelCornerRadius
        handleCornerRadius = Defaults.handleCornerRadius
        collapsedWidth = Defaults.collapsedWidth
        collapsedHeight = Defaults.collapsedHeight
        expandedWidth = Defaults.expandedWidth
        expandedHeight = Defaults.expandedHeight
        edgeInset = Defaults.edgeInset

        contentHorizontalPadding = Defaults.contentHorizontalPadding
        contentTopPadding = Defaults.contentTopPadding
        contentBottomPadding = Defaults.contentBottomPadding
        rowSpacing = Defaults.rowSpacing

        inputCornerRadius = Defaults.inputCornerRadius
        inputLeadingPadding = Defaults.inputLeadingPadding
        inputTrailingPadding = Defaults.inputTrailingPadding
        inputVerticalPadding = Defaults.inputVerticalPadding

        rowCornerRadius = Defaults.rowCornerRadius
        rowHorizontalPadding = Defaults.rowHorizontalPadding
        rowVerticalPadding = Defaults.rowVerticalPadding
        rowInnerSpacing = Defaults.rowInnerSpacing

        bodyTextSize = Defaults.bodyTextSize
        secondaryTextSize = Defaults.secondaryTextSize
        checkboxSize = Defaults.checkboxSize
        actionIconSize = Defaults.actionIconSize
        listIconSize = Defaults.listIconSize

        pillCornerRadius = Defaults.pillCornerRadius
        pillHorizontalPadding = Defaults.pillHorizontalPadding
        pillVerticalPadding = Defaults.pillVerticalPadding
        pillSpacing = Defaults.pillSpacing

        checkmarkSize = Defaults.checkmarkSize
        addListIconSize = Defaults.addListIconSize
    }

    private static func read(_ key: String, default fallback: CGFloat, from defaults: UserDefaults) -> CGFloat {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return CGFloat(defaults.double(forKey: key))
    }

    private func persist(_ value: CGFloat, _ key: String) {
        UserDefaults.standard.set(Double(value), forKey: key)
    }
}
