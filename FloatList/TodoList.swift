import Foundation
import AppKit
import SwiftUI

enum ListIconColor: String, Codable, CaseIterable, Equatable {
    case red, orange, yellow, green, teal, blue, indigo, purple, pink

    var color: Color { Self.cachedColors[self] ?? FloatListTheme.textPrimary }

    /// Per-appearance tuning: dark-mode values stay vivid against the
    /// translucent dark shell, light-mode values are darker / more saturated
    /// so they keep enough contrast against the white panel. Cached so the
    /// hot-path icon renders don't rebuild the dynamic-NSColor wrapper on
    /// every pass.
    private static let cachedColors: [ListIconColor: Color] = [
        .red:    .dynamic(light: Color(red: 0.82, green: 0.22, blue: 0.20),
                          dark:  Color(red: 0.93, green: 0.33, blue: 0.31)),
        .orange: .dynamic(light: Color(red: 0.84, green: 0.44, blue: 0.10),
                          dark:  Color(red: 0.96, green: 0.60, blue: 0.26)),
        .yellow: .dynamic(light: Color(red: 0.72, green: 0.54, blue: 0.05),
                          dark:  Color(red: 0.95, green: 0.78, blue: 0.22)),
        .green:  .dynamic(light: Color(red: 0.18, green: 0.55, blue: 0.28),
                          dark:  Color(red: 0.30, green: 0.74, blue: 0.42)),
        .teal:   .dynamic(light: Color(red: 0.10, green: 0.50, blue: 0.55),
                          dark:  Color(red: 0.27, green: 0.72, blue: 0.73)),
        .blue:   .dynamic(light: Color(red: 0.18, green: 0.42, blue: 0.85),
                          dark:  Color(red: 0.32, green: 0.60, blue: 0.95)),
        .indigo: .dynamic(light: Color(red: 0.30, green: 0.32, blue: 0.78),
                          dark:  Color(red: 0.43, green: 0.47, blue: 0.90)),
        .purple: .dynamic(light: Color(red: 0.50, green: 0.25, blue: 0.75),
                          dark:  Color(red: 0.67, green: 0.43, blue: 0.89)),
        .pink:   .dynamic(light: Color(red: 0.82, green: 0.28, blue: 0.55),
                          dark:  Color(red: 0.93, green: 0.46, blue: 0.68)),
    ]
}

struct TodoList: Identifiable, Codable, Equatable {
    static let defaultName = "New List"
    static let completedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let completedName = "Completed"
    static let completedIcon = "checkmark.circle.fill"
    static let trashID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let trashName = "Trash"
    static let trashIcon = "trash.fill"
    /// SF Symbol name shown as the list icon. All renderers apply
    /// `.symbolVariant(.fill)`, so prefer base names without `.fill`.
    static let defaultIcon = "checklist"
    static let completedList = TodoList(
        id: completedID,
        name: completedName,
        icon: completedIcon,
        createdAt: Date(timeIntervalSince1970: 0)
    )
    static let trashList = TodoList(
        id: trashID,
        name: trashName,
        icon: trashIcon,
        createdAt: Date(timeIntervalSince1970: 0)
    )

    let id: UUID
    var name: String
    var icon: String
    var iconColor: ListIconColor?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = TodoList.defaultIcon,
        iconColor: ListIconColor? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = TodoList.sanitize(icon)
        self.iconColor = iconColor
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, iconColor, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        let decoded = try container.decodeIfPresent(String.self, forKey: .icon)
        icon = TodoList.sanitize(decoded)
        iconColor = try container.decodeIfPresent(ListIconColor.self, forKey: .iconColor)
    }

    /// Accept only SF Symbol names; fall back to the default for empty strings
    /// or legacy emoji values carried over from older stores.
    static func sanitize(_ raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil
        else {
            return defaultIcon
        }
        return trimmed
    }
}
