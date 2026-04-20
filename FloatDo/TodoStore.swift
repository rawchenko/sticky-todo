import Foundation
import Combine
import AppKit

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
    static let currentSchemaVersion = 4

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
        if id == TodoList.trashID {
            return trashedItems
        }
        if id == TodoList.completedID {
            return completedItems
        }
        return activeItems(in: id)
    }

    var isTrashSelected: Bool {
        selectedListID == TodoList.trashID
    }

    var isCompletedSelected: Bool {
        selectedListID == TodoList.completedID
    }

    var isSpecialListSelected: Bool {
        isTrashSelected || isCompletedSelected
    }

    var hasTrashedItems: Bool {
        items.contains(where: { $0.isTrashed })
    }

    var hasCompletedItems: Bool {
        items.contains(where: { $0.isCompleted && !$0.isTrashed })
    }

    /// Items belonging to the given list, in flat-array order.
    func items(in listID: UUID) -> [TodoItem] {
        if listID == TodoList.completedID {
            return completedItems
        }
        if listID == TodoList.trashID {
            return trashedItems
        }
        return items.filter { $0.listID == listID }
    }

    func activeItems(in listID: UUID) -> [TodoItem] {
        items.filter { $0.listID == listID && !$0.isCompleted && !$0.isTrashed }
    }

    func completedItems(in listID: UUID) -> [TodoItem] {
        items.filter { $0.listID == listID && $0.isCompleted && !$0.isTrashed }
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
                selectedListID = normalizedSelection(file.selectedListID)
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
        guard !isSpecialListID(listID) else { return }
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
        guard let listID = items[idx].listID, !isSpecialListID(listID) else { return }

        var updated = items.remove(at: idx)
        updated.isCompleted.toggle()

        let destination = insertionIndex(
            for: listID,
            insertingCompleted: updated.isCompleted,
            fallback: idx
        )
        items.insert(updated, at: destination)
        save()
    }

    func delete(_ item: TodoItem) {
        moveToTrash(item)
    }

    func moveToTrash(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        moveItemToTrash(at: idx)
        save()
    }

    func restore(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[idx].isTrashed else { return }

        let priorSelection = selectedListID
        let targetListID: UUID
        if let originalListID = items[idx].trashedOriginalListID,
           lists.contains(where: { $0.id == originalListID }) {
            targetListID = originalListID
        } else {
            let recreatedList = TodoList(name: restoreListName(for: items[idx]))
            lists.append(recreatedList)
            targetListID = recreatedList.id
        }

        items[idx].listID = targetListID
        items[idx].trashedAt = nil
        items[idx].trashedOriginalListID = nil
        items[idx].trashedOriginalListName = nil
        selectedListID = priorSelection
        save()
    }

    func permanentlyDelete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        if selectedListID == TodoList.trashID && lists.isEmpty && !hasTrashedItems {
            selectedListID = nil
        }
        save()
    }

    func emptyTrash() {
        items.removeAll(where: { $0.isTrashed })
        if selectedListID == TodoList.trashID && lists.isEmpty {
            selectedListID = nil
        }
        save()
    }

    func originalListName(for item: TodoItem) -> String {
        if let originalListID = item.trashedOriginalListID,
           let liveName = listName(for: originalListID) {
            return liveName
        }
        return item.trashedOriginalListName ?? listName(for: item.listID) ?? TodoList.defaultName
    }

    func sourceListName(for item: TodoItem) -> String {
        if item.isTrashed {
            return originalListName(for: item)
        }
        return listName(for: item.listID) ?? TodoList.defaultName
    }

    /// Reorder an item within the currently selected list. Indices refer to
    /// positions in the visible incomplete items of the selected regular list.
    func move(from: Int, to: Int) {
        guard let listID = selectedListID else { return }
        guard !isSpecialListID(listID) else { return }
        let listItems = activeItems(in: listID)
        guard listItems.indices.contains(from), from != to else { return }

        let moving = listItems[from]
        items.removeAll { $0.id == moving.id }

        let newListItems = activeItems(in: listID)
        let destinationAbsolute: Int
        if to >= newListItems.count {
            if let firstCompletedIdx = items.firstIndex(where: { $0.listID == listID && $0.isCompleted }) {
                destinationAbsolute = firstCompletedIdx
            } else if let lastListIdx = items.lastIndex(where: { $0.listID == listID }) {
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
        let list = TodoList(name: finalName, icon: TodoList.sanitize(icon))
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
        guard !trimmed.isEmpty,
              NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil
        else { return }
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        guard lists[idx].icon != trimmed else { return }
        lists[idx].icon = trimmed
        save()
    }

    func deleteList(_ list: TodoList) {
        guard !isSpecialListID(list.id) else { return }
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        for itemIndex in items.indices where items[itemIndex].listID == list.id {
            moveItemToTrash(at: itemIndex, originalList: list)
        }
        lists.remove(at: idx)
        if selectedListID == list.id {
            selectedListID = lists.first?.id ?? fallbackVirtualSelection()
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
        guard id == nil || isSpecialListID(id) || lists.contains(where: { $0.id == id }) else { return }
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
            copy.trashedAt = nil
            copy.trashedOriginalListID = nil
            copy.trashedOriginalListName = nil
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

    private func normalizedSelection(_ candidate: UUID?) -> UUID? {
        if isSpecialListID(candidate) {
            return candidate
        }
        if let candidate, lists.contains(where: { $0.id == candidate }) {
            return candidate
        }
        if let firstListID = lists.first?.id {
            return firstListID
        }
        return fallbackVirtualSelection()
    }

    private func restoreListName(for item: TodoItem) -> String {
        let trimmed = item.trashedOriginalListName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Tasks" : trimmed
    }

    private func listName(for id: UUID?) -> String? {
        guard let id else { return nil }
        if id == TodoList.completedID {
            return TodoList.completedName
        }
        if id == TodoList.trashID {
            return TodoList.trashName
        }
        return lists.first(where: { $0.id == id })?.name
    }

    private var completedItems: [TodoItem] {
        items.filter { $0.isCompleted && !$0.isTrashed }
    }

    private var trashedItems: [TodoItem] {
        items.filter(\.isTrashed)
    }

    private func moveItemToTrash(at index: Int, originalList: TodoList? = nil) {
        guard items.indices.contains(index) else { return }
        guard !items[index].isTrashed else { return }

        let originalListID = items[index].listID
        let originalListName = originalList?.name ?? listName(for: originalListID) ?? TodoList.defaultName

        items[index].listID = TodoList.trashID
        items[index].trashedAt = Date()
        items[index].trashedOriginalListID = originalListID
        items[index].trashedOriginalListName = originalListName
    }

    private func insertionIndex(for listID: UUID, insertingCompleted: Bool, fallback: Int) -> Int {
        if insertingCompleted {
            if let lastListIdx = items.lastIndex(where: { $0.listID == listID }) {
                return lastListIdx + 1
            }
        } else {
            if let firstCompletedIdx = items.firstIndex(where: { $0.listID == listID && $0.isCompleted }) {
                return firstCompletedIdx
            }
            if let lastListIdx = items.lastIndex(where: { $0.listID == listID }) {
                return lastListIdx + 1
            }
        }

        return min(fallback, items.count)
    }

    private func fallbackVirtualSelection() -> UUID? {
        if hasCompletedItems {
            return TodoList.completedID
        }
        if hasTrashedItems {
            return TodoList.trashID
        }
        return nil
    }

    private func isSpecialListID(_ id: UUID?) -> Bool {
        id == TodoList.completedID || id == TodoList.trashID
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FloatDo")
        return appDir.appendingPathComponent("todos.json")
    }
}
