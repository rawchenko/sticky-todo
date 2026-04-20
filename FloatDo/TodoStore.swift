import Foundation
import Combine

struct TodoStoreRecoveryNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let backupURL: URL?
}

struct TodoStoreFile: Codable {
    var schemaVersion: Int
    var lists: [TodoList]
    var todos: [TodoItem]
    var selectedListID: UUID?
}

class TodoStore: ObservableObject {
    static let currentSchemaVersion = 3

    @Published var items: [TodoItem] = []
    @Published var lists: [TodoList] = []
    @Published var selectedListID: UUID?
    @Published var recoveryNotice: TodoStoreRecoveryNotice?

    private let fileURL: URL
    private let fileManager: FileManager
    private var isStorageWritable = true

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        let directoryURL = self.fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        load()
    }

    var visibleItems: [TodoItem] {
        guard let id = selectedListID else { return [] }
        return items.filter { $0.listID == id }
    }

    /// Items belonging to the given list, in flat-array order.
    func items(in listID: UUID) -> [TodoItem] {
        items.filter { $0.listID == listID }
    }

    func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            items = []
            lists = []
            selectedListID = nil
            isStorageWritable = true
            recoveryNotice = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)

            if let file = try? JSONDecoder().decode(TodoStoreFile.self, from: data) {
                lists = file.lists
                items = file.todos
                selectedListID = file.selectedListID ?? file.lists.first?.id
                isStorageWritable = true
                recoveryNotice = nil
                return
            }

            let legacyItems = try JSONDecoder().decode([TodoItem].self, from: data)
            migrateFromLegacy(legacyItems)
        } catch {
            recoverUnreadableStore(after: error)
        }
    }

    func save() {
        guard isStorageWritable else { return }
        let file = TodoStoreFile(
            schemaVersion: Self.currentSchemaVersion,
            lists: lists,
            todos: items,
            selectedListID: selectedListID
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Todos

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let listID = selectedListID else { return }
        items.append(TodoItem(title: trimmed, listID: listID))
        save()
    }

    func rename(_ item: TodoItem, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[idx].title != trimmed else { return }
        items[idx].title = trimmed
        save()
    }

    func toggle(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isCompleted.toggle()
        save()
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Reorder an item within the currently selected list. Indices refer to
    /// positions in `items(in: selectedListID)`.
    func move(from: Int, to: Int) {
        guard let listID = selectedListID else { return }
        let listItems = items(in: listID)
        guard listItems.indices.contains(from), from != to else { return }

        let moving = listItems[from]
        items.removeAll { $0.id == moving.id }

        let newListItems = items(in: listID)
        let destinationAbsolute: Int
        if to >= newListItems.count {
            if let lastListIdx = items.lastIndex(where: { $0.listID == listID }) {
                destinationAbsolute = lastListIdx + 1
            } else {
                destinationAbsolute = items.count
            }
        } else {
            let targetItem = newListItems[to]
            destinationAbsolute = items.firstIndex(where: { $0.id == targetItem.id }) ?? items.count
        }

        items.insert(moving, at: destinationAbsolute)
        save()
    }

    // MARK: - Lists

    @discardableResult
    func addList(name: String, icon: String = TodoList.defaultIcon) -> TodoList {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? TodoList.defaultName : trimmed
        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalIcon = trimmedIcon.isEmpty ? TodoList.defaultIcon : trimmedIcon
        let list = TodoList(name: finalName, icon: finalIcon)
        lists.append(list)
        selectedListID = list.id
        save()
        return list
    }

    func renameList(_ list: TodoList, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        guard lists[idx].name != trimmed else { return }
        lists[idx].name = trimmed
        save()
    }

    func setListIcon(_ list: TodoList, to icon: String) {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        guard lists[idx].icon != trimmed else { return }
        lists[idx].icon = trimmed
        save()
    }

    func deleteList(_ list: TodoList) {
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        items.removeAll { $0.listID == list.id }
        lists.remove(at: idx)
        if selectedListID == list.id {
            selectedListID = lists.first?.id
        }
        save()
    }

    func moveList(from: Int, to: Int) {
        guard lists.indices.contains(from),
              to >= 0, to < lists.count,
              from != to else { return }
        let list = lists.remove(at: from)
        lists.insert(list, at: to)
        save()
    }

    func selectList(_ id: UUID?) {
        guard selectedListID != id else { return }
        selectedListID = id
        save()
    }

    // MARK: - Migration / recovery

    private func migrateFromLegacy(_ legacyItems: [TodoItem]) {
        let defaultList = TodoList(name: "Tasks")
        lists = [defaultList]
        items = legacyItems.map { item in
            var copy = item
            copy.listID = defaultList.id
            return copy
        }
        selectedListID = defaultList.id
        isStorageWritable = true
        recoveryNotice = nil
        save()
    }

    private func recoverUnreadableStore(after decodeError: Error) {
        let backupURL = makeBackupURL()

        do {
            try fileManager.moveItem(at: fileURL, to: backupURL)
            items = []
            lists = []
            selectedListID = nil
            isStorageWritable = true
            recoveryNotice = TodoStoreRecoveryNotice(
                message: "Your todo file was unreadable. A backup was saved and the list was reset.",
                backupURL: backupURL
            )
        } catch {
            items = []
            lists = []
            selectedListID = nil
            isStorageWritable = false
            recoveryNotice = TodoStoreRecoveryNotice(
                message: "Your todo file was unreadable and could not be moved to a backup. Saving is paused to avoid overwriting it.",
                backupURL: nil
            )
            NSLog("FloatDo failed to decode todo file: %@", String(describing: decodeError))
            NSLog("FloatDo failed to move unreadable todo file to backup: %@", String(describing: error))
        }
    }

    private func makeBackupURL() -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let directoryURL = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let pathExtension = fileURL.pathExtension
        let timestamp = formatter.string(from: Date())

        var candidate = directoryURL.appendingPathComponent("\(baseName)-corrupted-\(timestamp)")
        if !pathExtension.isEmpty {
            candidate.appendPathExtension(pathExtension)
        }

        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        var uniqueCandidate = directoryURL.appendingPathComponent("\(baseName)-corrupted-\(timestamp)-\(UUID().uuidString)")
        if !pathExtension.isEmpty {
            uniqueCandidate.appendPathExtension(pathExtension)
        }
        return uniqueCandidate
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FloatDo")
        return appDir.appendingPathComponent("todos.json")
    }
}
