import Foundation

struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var listID: UUID?
    var trashedAt: Date?
    var trashedOriginalListID: UUID?
    var trashedOriginalListName: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        listID: UUID? = nil,
        trashedAt: Date? = nil,
        trashedOriginalListID: UUID? = nil,
        trashedOriginalListName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.listID = listID
        self.trashedAt = trashedAt
        self.trashedOriginalListID = trashedOriginalListID
        self.trashedOriginalListName = trashedOriginalListName
        self.createdAt = createdAt
    }

    var isTrashed: Bool {
        listID == TodoList.trashID
    }
}
