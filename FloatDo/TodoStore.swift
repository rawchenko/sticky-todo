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

    /// Top-level items (no parent) for the given list, in flat-array order.
    func topLevelItems(in listID: UUID) -> [TodoItem] {
        items.filter { $0.listID == listID && $0.parentID == nil }
    }

    /// Children of a given parent, in flat-array order.
    func children(of parentID: UUID) -> [TodoItem] {
        items.filter { $0.parentID == parentID }
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
                sanitizeHierarchy()
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

    /// Insert a new subtask under `parentID`. Placed after the parent's last
    /// existing child to preserve the contiguous-block invariant.
    func addSubtask(title: String, parentID: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let parentIdx = items.firstIndex(where: { $0.id == parentID && $0.parentID == nil }) else { return }
        let parent = items[parentIdx]
        let child = TodoItem(title: trimmed, listID: parent.listID, parentID: parentID)

        let insertIdx: Int
        if let lastChildIdx = items.lastIndex(where: { $0.parentID == parentID }) {
            insertIdx = lastChildIdx + 1
        } else {
            insertIdx = parentIdx + 1
        }
        items.insert(child, at: insertIdx)
        reconcileParent(parentID)
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
        let newValue = !items[idx].isCompleted
        items[idx].isCompleted = newValue

        if items[idx].parentID == nil {
            for i in items.indices where items[i].parentID == item.id {
                items[i].isCompleted = newValue
            }
        } else if let pid = items[idx].parentID {
            reconcileParent(pid)
        }
        save()
    }

    func delete(_ item: TodoItem) {
        if item.parentID == nil {
            items.removeAll { $0.id == item.id || $0.parentID == item.id }
        } else {
            let pid = item.parentID
            items.removeAll { $0.id == item.id }
            if let pid = pid {
                reconcileParent(pid)
            }
        }
        save()
    }

    /// Reorder a top-level item within the currently selected list. Indices refer
    /// to positions in `topLevelItems(in: selectedListID)`. The parent's children
    /// move with it as a contiguous block.
    func moveTopLevel(from: Int, to: Int) {
        guard let listID = selectedListID else { return }
        let topLevel = topLevelItems(in: listID)
        guard topLevel.indices.contains(from), from != to else { return }

        let parent = topLevel[from]
        let blockIDs = Set(
            items
                .filter { $0.id == parent.id || ($0.listID == listID && $0.parentID == parent.id) }
                .map(\.id)
        )
        let block = items.filter { blockIDs.contains($0.id) }
        items.removeAll { blockIDs.contains($0.id) }

        let newTopLevel = topLevelItems(in: listID)
        let destinationAbsolute: Int
        if to >= newTopLevel.count {
            if let lastListIdx = items.lastIndex(where: { $0.listID == listID }) {
                destinationAbsolute = lastListIdx + 1
            } else {
                destinationAbsolute = items.count
            }
        } else {
            let targetParent = newTopLevel[to]
            destinationAbsolute = items.firstIndex(where: { $0.id == targetParent.id }) ?? items.count
        }

        items.insert(contentsOf: block, at: destinationAbsolute)
        save()
    }

    /// Reorder a child within its parent's sibling slice. Indices refer to
    /// positions in `children(of: parentID)`.
    func moveChild(parentID: UUID, from: Int, to: Int) {
        let siblings = children(of: parentID)
        guard siblings.indices.contains(from), from != to else { return }

        let child = siblings[from]
        items.removeAll { $0.id == child.id }

        let newSiblings = children(of: parentID)
        let destinationAbsolute: Int
        if to >= newSiblings.count {
            if let lastChildIdx = items.lastIndex(where: { $0.parentID == parentID }) {
                destinationAbsolute = lastChildIdx + 1
            } else if let parentIdx = items.firstIndex(where: { $0.id == parentID }) {
                destinationAbsolute = parentIdx + 1
            } else {
                return
            }
        } else {
            let targetChild = newSiblings[to]
            destinationAbsolute = items.firstIndex(where: { $0.id == targetChild.id }) ?? items.count
        }

        items.insert(child, at: destinationAbsolute)
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

    // MARK: - Hierarchy invariants

    /// Enforce `parent.isCompleted == children.allSatisfy(\.isCompleted)` whenever
    /// the parent has children. A parent with zero children keeps its current state.
    private func reconcileParent(_ parentID: UUID) {
        let siblings = items.filter { $0.parentID == parentID }
        guard !siblings.isEmpty else { return }
        let allComplete = siblings.allSatisfy { $0.isCompleted }
        guard let parentIdx = items.firstIndex(where: { $0.id == parentID }) else { return }
        if items[parentIdx].isCompleted != allComplete {
            items[parentIdx].isCompleted = allComplete
        }
    }

    /// Drop orphaned children and enforce the contiguous-block invariant on load.
    private func sanitizeHierarchy() {
        let parentByID: [UUID: TodoItem] = Dictionary(
            uniqueKeysWithValues: items.filter { $0.parentID == nil }.map { ($0.id, $0) }
        )
        items.removeAll { item in
            guard let pid = item.parentID else { return false }
            guard let parent = parentByID[pid] else { return true }
            return parent.listID != item.listID
        }

        var rebuilt: [TodoItem] = []
        var emittedChildIDs = Set<UUID>()

        for item in items {
            if item.parentID == nil {
                rebuilt.append(item)
                for child in items where child.parentID == item.id {
                    if emittedChildIDs.insert(child.id).inserted {
                        rebuilt.append(child)
                    }
                }
            }
        }

        items = rebuilt
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
        sanitizeHierarchy()
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
