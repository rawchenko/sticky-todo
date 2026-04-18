import Foundation

struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var listID: UUID?
    var parentID: UUID?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        listID: UUID? = nil,
        parentID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.listID = listID
        self.parentID = parentID
        self.createdAt = createdAt
    }
}
