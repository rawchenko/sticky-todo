import Foundation
import AppKit

struct TodoList: Identifiable, Codable, Equatable {
    static let defaultName = "New List"
    static let trashID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let trashName = "Trash"
    static let trashIcon = "trash"
    /// SF Symbol name shown as the list icon. All renderers apply
    /// `.symbolVariant(.fill)`, so prefer base names without `.fill`.
    static let defaultIcon = "checklist"
    static let trashList = TodoList(
        id: trashID,
        name: trashName,
        icon: trashIcon,
        createdAt: Date(timeIntervalSince1970: 0)
    )

    let id: UUID
    var name: String
    var icon: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = TodoList.defaultIcon,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = TodoList.sanitize(icon)
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        let decoded = try container.decodeIfPresent(String.self, forKey: .icon)
        icon = TodoList.sanitize(decoded)
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
