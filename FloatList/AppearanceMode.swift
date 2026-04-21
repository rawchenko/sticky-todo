import AppKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // AppKit propagates the new appearance asynchronously, and the glass /
        // NSVisualEffectView backing can latch onto a stale frame if the panel
        // is mid-resize — leaving a rectangle of the window rendered with the
        // old appearance. Force every window to rebuild its effect layers at
        // the current frame so the two halves stay consistent.
        for window in NSApp.windows {
            guard let contentView = window.contentView else { continue }
            contentView.needsDisplay = true
            refreshVisualEffectViews(in: contentView)
        }
    }

    private func refreshVisualEffectViews(in view: NSView) {
        if let effect = view as? NSVisualEffectView {
            let previous = effect.state
            effect.state = .inactive
            effect.state = previous
            effect.needsDisplay = true
        }
        for subview in view.subviews {
            refreshVisualEffectViews(in: subview)
        }
    }

    static let storageKey = "floatlist.settings.appearance"

    static var current: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppearanceMode.system.rawValue
        return AppearanceMode(rawValue: raw) ?? .system
    }
}
