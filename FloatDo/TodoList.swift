import Foundation

struct TodoList: Identifiable, Codable, Equatable {
    static let defaultName = "New List"
    static let defaultIcon = "📝"

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
        self.icon = icon
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

        let decoded = try container.decodeIfPresent(String.self, forKey: .icon)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded, !decoded.isEmpty {
            icon = decoded
        } else {
            icon = TodoList.defaultIcon
        }
    }
}
