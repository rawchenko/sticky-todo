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
    }

    static let storageKey = "floatlist.settings.appearance"

    static var current: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppearanceMode.system.rawValue
        return AppearanceMode(rawValue: raw) ?? .system
    }
}
