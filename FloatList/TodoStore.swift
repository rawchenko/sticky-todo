import Foundation
import Combine
import AppKit
import Darwin

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

@MainActor
final class TodoStore: ObservableObject {
    static let currentSchemaVersion = 4
    static let maxTodoTitleLength = 280
    static let maxListNameLength = 80

    private static let storeLoadMaxBytes: Int = 5 * 1024 * 1024

    private enum StoreLoadIssue: Error {
        case unsupportedFileType
        case fileTooLarge(Int)
    }

    @Published var items: [TodoItem] = []
    @Published var lists: [TodoList] = []
    @Published var selectedListID: UUID?
    @Published var recoveryNotice: TodoStoreRecoveryNotice?
    @Published private(set) var canUndo: Bool = false

    private struct UndoSnapshot {
        let items: [TodoItem]
        let lists: [TodoList]
        let selectedListID: UUID?
    }

    private var undoStack: [UndoSnapshot] = []
    private let undoStackLimit = 50

    private let fileURL: URL
    private let fileManager: FileManager
    private let inMemory: Bool
    private var isStorageWritable = true
    private var isBatching = false

    var isReadOnly: Bool {
        !isStorageWritable
    }

    init(fileURL: URL? = nil, fileManager: FileManager = .default, inMemory: Bool = false) {
        self.fileManager = fileManager
        let usesDefaultFileURL = fileURL == nil
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.inMemory = inMemory
        var didMigrateLegacyStore = false
        if !inMemory {
            let directoryURL = self.fileURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            if usesDefaultFileURL {
                didMigrateLegacyStore = migrateLegacyStoreIfNeeded()
            }
        }
        load()
        if didMigrateLegacyStore, recoveryNotice == nil {
            recoveryNotice = TodoStoreRecoveryNotice(
                message: "Migrated existing data from previous install.",
                backupURL: nil
            )
        }
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
        defer { ensureDefaultInboxIfEmpty() }

        if inMemory || !fileManager.fileExists(atPath: fileURL.path) {
            items = []
            lists = []
            selectedListID = nil
            isStorageWritable = true
            recoveryNotice = nil
            return
        }

        do {
            let data = try loadStoreData()

            if let file = try? JSONDecoder().decode(TodoStoreFile.self, from: data) {
                if file.schemaVersion > Self.currentSchemaVersion {
                    presentUnsupportedSchemaVersion(file.schemaVersion)
                    return
                }
                // Add explicit per-version migrations here when a future schema bump breaks backward compatibility.
                let sanitized = Self.sanitizeDecoded(lists: file.lists, items: file.todos)
                lists = sanitized.lists
                items = sanitized.items
                selectedListID = normalizedSelection(file.selectedListID)
                isStorageWritable = true
                recoveryNotice = sanitized.didFixUp
                    ? TodoStoreRecoveryNotice(
                        message: "Your todo file contained invalid entries that were cleaned up.",
                        backupURL: nil
                    )
                    : nil
                return
            }

            let legacyItems = try JSONDecoder().decode([TodoItem].self, from: data)
            migrateFromLegacy(legacyItems)
        } catch let issue as StoreLoadIssue {
            presentBlockedStore(issue)
        } catch {
            recoverUnreadableStore(after: error)
        }
    }

    /// Populate a fresh/empty store with a default `Inbox` so the app always
    /// boots into a valid state with a selected regular list. Runs outside the
    /// undo stack so ordinary `undo()` can never strip the precreated list.
    private func ensureDefaultInboxIfEmpty() {
        guard isStorageWritable else { return }
        guard lists.isEmpty, items.isEmpty else { return }

        let inbox = TodoList(id: TodoList.inboxID, name: TodoList.inboxName)
        lists.append(inbox)
        selectedListID = inbox.id
        save()
    }

    func save() {
        guard !inMemory else { return }
        guard isStorageWritable else { return }
        guard !isBatching else { return }
        let file = TodoStoreFile(
            schemaVersion: Self.currentSchemaVersion,
            lists: lists,
            todos: items,
            selectedListID: selectedListID
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Undo

    private func captureUndoSnapshot() {
        guard !isReadOnly else { return }
        guard !isBatching else { return }
        undoStack.append(UndoSnapshot(items: items, lists: lists, selectedListID: selectedListID))
        if undoStack.count > undoStackLimit {
            undoStack.removeFirst(undoStack.count - undoStackLimit)
        }
        if !canUndo { canUndo = true }
    }

    private func performBatch(_ body: () -> Void) {
        guard !isReadOnly else { return }
        captureUndoSnapshot()
        isBatching = true
        body()
        isBatching = false
        save()
    }

    func undo() {
        guard !isReadOnly else { return }
        guard let snapshot = undoStack.popLast() else { return }
        items = snapshot.items
        lists = snapshot.lists
        selectedListID = snapshot.selectedListID
        let stillHasHistory = !undoStack.isEmpty
        if canUndo != stillHasHistory { canUndo = stillHasHistory }
        save()
    }

    // MARK: - Import

    /// Merges items from another store into this one. Used by the
    /// Immersive onboarding flow to migrate tasks created in the temporary
    /// in-memory store into the user's real Inbox. Preserves completion
    /// and trash state; trashed items retain their trashID listing and
    /// point their `trashedOriginalListID` back at the real Inbox so
    /// the Restore action works as expected.
    ///
    /// No-op when `incoming` is empty, so it's safe to call on close
    /// even if the user didn't add anything.
    func importOnboardingItems(_ incoming: [TodoItem]) {
        guard !isReadOnly else { return }
        guard !incoming.isEmpty else { return }
        let inboxID = TodoList.inboxID
        let inboxName = TodoList.inboxName

        captureUndoSnapshot()
        // The default-inbox seeding only runs on a completely empty
        // store — a user who deleted the Inbox before onboarding would
        // end up with orphaned items whose listID points at a list
        // that isn't in the sidebar. Re-create the Inbox in that case
        // so migrated tasks are actually reachable.
        if !lists.contains(where: { $0.id == inboxID }) {
            lists.insert(TodoList(id: inboxID, name: inboxName), at: 0)
        }
        for source in incoming {
            var copy = source
            if source.isTrashed {
                // Keep trash placement but repoint origin to real Inbox.
                copy.trashedOriginalListID = inboxID
                copy.trashedOriginalListName = inboxName
            } else {
                // Route everything else (active + completed) into Inbox.
                copy.listID = inboxID
            }
            items.append(copy)
        }
        save()
    }

    // MARK: - Todos

    func add(title: String) {
        guard !isReadOnly else { return }
        guard let trimmed = Self.normalizedTodoTitleInput(title) else { return }
        guard let listID = selectedListID else { return }
        guard !isSpecialListID(listID) else { return }
        captureUndoSnapshot()
        items.append(TodoItem(title: trimmed, listID: listID))
        save()
    }

    func rename(_ item: TodoItem, to newTitle: String) {
        guard !isReadOnly else { return }
        guard let trimmed = Self.normalizedTodoTitleInput(newTitle) else { return }
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[idx].title != trimmed else { return }
        captureUndoSnapshot()
        items[idx].title = trimmed
        save()
    }

    func toggle(_ item: TodoItem) {
        guard !isReadOnly else { return }
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard let listID = items[idx].listID, !isSpecialListID(listID) else { return }

        captureUndoSnapshot()
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
        guard !isReadOnly else { return }
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        captureUndoSnapshot()
        moveItemToTrash(at: idx)
        save()
    }

    func restore(_ item: TodoItem) {
        guard !isReadOnly else { return }
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[idx].isTrashed else { return }

        captureUndoSnapshot()
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
        guard !isReadOnly else { return }
        guard items.contains(where: { $0.id == item.id }) else { return }
        captureUndoSnapshot()
        items.removeAll { $0.id == item.id }
        if selectedListID == TodoList.trashID && lists.isEmpty && !hasTrashedItems {
            selectedListID = nil
        }
        save()
    }

    func emptyTrash() {
        guard !isReadOnly else { return }
        guard hasTrashedItems else { return }
        captureUndoSnapshot()
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
        guard !isReadOnly else { return }
        guard let listID = selectedListID else { return }
        guard !isSpecialListID(listID) else { return }
        let listItems = activeItems(in: listID)
        guard listItems.indices.contains(from), from != to else { return }

        captureUndoSnapshot()
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

    // MARK: - Bulk actions

    private func applyMany(
        _ items: [TodoItem],
        filter: (TodoItem) -> Bool,
        action: (TodoItem) -> Void
    ) {
        guard !isReadOnly else { return }
        let targets = items.filter(filter)
        guard !targets.isEmpty else { return }
        performBatch {
            for item in targets { action(item) }
        }
    }

    func toggleMany(_ items: [TodoItem]) {
        applyMany(items,
                  filter: { item in item.listID.map { !self.isSpecialListID($0) } ?? false },
                  action: toggle)
    }

    func moveManyToTrash(_ items: [TodoItem]) {
        applyMany(items, filter: { !$0.isTrashed }, action: moveToTrash)
    }

    func restoreMany(_ items: [TodoItem]) {
        applyMany(items, filter: { $0.isTrashed }, action: restore)
    }

    func permanentlyDeleteMany(_ items: [TodoItem]) {
        guard !isReadOnly else { return }
        let ids = Set(items.map { $0.id })
        guard !ids.isEmpty, self.items.contains(where: { ids.contains($0.id) }) else { return }
        performBatch {
            self.items.removeAll { ids.contains($0.id) }
            if selectedListID == TodoList.trashID && lists.isEmpty && !hasTrashedItems {
                selectedListID = nil
            }
        }
    }

    func moveItems(_ items: [TodoItem], to targetListID: UUID) {
        guard !isSpecialListID(targetListID) else { return }
        guard lists.contains(where: { $0.id == targetListID }) else { return }
        applyMany(items,
                  filter: { !$0.isTrashed && $0.listID != targetListID },
                  action: { self.moveItem($0, to: targetListID) })
    }

    // MARK: - Lists

    @discardableResult
    func addList(name: String, icon: String = TodoList.defaultIcon) -> TodoList {
        let finalName = Self.normalizedListNameInput(name, fallback: TodoList.defaultName)
        let list = TodoList(name: finalName, icon: TodoList.sanitize(icon))
        guard !isReadOnly else { return list }
        captureUndoSnapshot()
        lists.append(list)
        selectedListID = list.id
        save()
        return list
    }

    func renameList(_ list: TodoList, to newName: String) {
        guard !isReadOnly else { return }
        guard let trimmed = Self.normalizedListNameInput(newName) else { return }
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        guard lists[idx].name != trimmed else { return }
        captureUndoSnapshot()
        lists[idx].name = trimmed
        save()
    }

    func setListIcon(_ list: TodoList, to icon: String) {
        guard !isReadOnly else { return }
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil
        else { return }
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        guard lists[idx].icon != trimmed else { return }
        captureUndoSnapshot()
        lists[idx].icon = trimmed
        save()
    }

    func setListColor(_ list: TodoList, to color: ListIconColor?) {
        guard !isReadOnly else { return }
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        guard lists[idx].iconColor != color else { return }
        captureUndoSnapshot()
        lists[idx].iconColor = color
        save()
    }

    func deleteList(_ list: TodoList) {
        guard !isReadOnly else { return }
        guard !isSpecialListID(list.id) else { return }
        guard let idx = lists.firstIndex(where: { $0.id == list.id }) else { return }
        captureUndoSnapshot()
        for itemIndex in items.indices where items[itemIndex].listID == list.id {
            moveItemToTrash(at: itemIndex, originalList: list)
        }
        lists.remove(at: idx)
        if selectedListID == list.id {
            selectedListID = lists.first?.id ?? fallbackVirtualSelection()
        }
        save()
    }

    /// Move an item into a different regular list, preserving the active/completed
    /// ordering of the destination. No-ops for trashed items, special lists, or
    /// when the target is the item's current list.
    func moveItem(_ item: TodoItem, to targetListID: UUID) {
        guard !isReadOnly else { return }
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard !items[idx].isTrashed else { return }
        guard !isSpecialListID(targetListID) else { return }
        guard lists.contains(where: { $0.id == targetListID }) else { return }
        guard items[idx].listID != targetListID else { return }

        captureUndoSnapshot()
        var moving = items.remove(at: idx)
        moving.listID = targetListID
        let destination = insertionIndex(
            for: targetListID,
            insertingCompleted: moving.isCompleted,
            fallback: items.count
        )
        items.insert(moving, at: destination)
        save()
    }

    func moveList(from: Int, to: Int) {
        guard !isReadOnly else { return }
        guard lists.indices.contains(from),
              to >= 0, to < lists.count,
              from != to else { return }
        captureUndoSnapshot()
        let list = lists.remove(at: from)
        lists.insert(list, at: to)
        save()
    }

    func selectList(_ id: UUID?) {
        guard !isReadOnly else { return }
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
            copy.title = Self.clampedPersistedTodoTitle(copy.title)
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
            NSLog("FloatList failed to decode todo file: %@", String(describing: decodeError))
            NSLog("FloatList failed to move unreadable todo file to backup: %@", String(describing: error))
        }
    }

    private func presentBlockedStore(_ issue: StoreLoadIssue) {
        items = []
        lists = []
        selectedListID = nil
        isStorageWritable = false

        let message: String
        switch issue {
        case .unsupportedFileType:
            message = "Your todo file could not be read as a regular file and was left untouched. Saving is paused to avoid overwriting it."
        case .fileTooLarge:
            message = "Your todo file exceeded the supported size and was left untouched. Saving is paused to avoid overwriting it."
        }

        recoveryNotice = TodoStoreRecoveryNotice(message: message, backupURL: nil)

        switch issue {
        case .unsupportedFileType:
            NSLog("FloatList todo file at %@ is not a regular file", fileURL.path)
        case .fileTooLarge(let bytes):
            NSLog("FloatList todo file at %@ exceeds max size %@ bytes", fileURL.path, String(bytes))
        }
    }

    private func loadStoreData() throws -> Data {
        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])

        if resourceValues.isRegularFile == false {
            throw StoreLoadIssue.unsupportedFileType
        }

        if let fileSize = resourceValues.fileSize, fileSize > Self.storeLoadMaxBytes {
            throw StoreLoadIssue.fileTooLarge(fileSize)
        }

        return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    }

    private func presentUnsupportedSchemaVersion(_ version: Int) {
        items = []
        lists = []
        selectedListID = nil
        isStorageWritable = false
        recoveryNotice = TodoStoreRecoveryNotice(
            message: "Your todo file was created by a newer FloatList version and was left untouched. Saving is paused to avoid overwriting it.",
            backupURL: nil
        )
        NSLog(
            "FloatList unsupported todo schemaVersion %@ (supported %@)",
            String(version),
            String(Self.currentSchemaVersion)
        )
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
        Self.normalizedListNameInput(item.trashedOriginalListName ?? "", fallback: "Tasks")
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

    /// Reject persisted lists that impersonate the virtual Trash/Completed
    /// rows, drop duplicate IDs (keeping the first), and re-home items whose
    /// `listID` points at a list that no longer exists. Trashed items keep
    /// their `trashID` listing; the check is purely about regular-list refs.
    private static func sanitizeDecoded(
        lists decodedLists: [TodoList],
        items decodedItems: [TodoItem]
    ) -> (lists: [TodoList], items: [TodoItem], didFixUp: Bool) {
        var seenIDs = Set<UUID>()
        var cleanedLists: [TodoList] = []
        var didFixUp = false

        for list in decodedLists {
            if list.id == TodoList.trashID || list.id == TodoList.completedID {
                didFixUp = true
                continue
            }
            if !seenIDs.insert(list.id).inserted {
                didFixUp = true
                continue
            }
            var sanitizedList = list
            let clampedName = normalizedListNameInput(list.name, fallback: TodoList.defaultName)
            if clampedName != list.name {
                sanitizedList.name = clampedName
                didFixUp = true
            }
            cleanedLists.append(sanitizedList)
        }

        var validListIDs = Set(cleanedLists.map(\.id))

        var cleanedItems: [TodoItem] = []
        cleanedItems.reserveCapacity(decodedItems.count)
        for item in decodedItems {
            var sanitizedItem = item
            let clampedTitle = clampedPersistedTodoTitle(item.title)
            if clampedTitle != item.title {
                sanitizedItem.title = clampedTitle
                didFixUp = true
            }
            let clampedOriginalListName = clampedPersistedListName(item.trashedOriginalListName)
            if clampedOriginalListName != item.trashedOriginalListName {
                sanitizedItem.trashedOriginalListName = clampedOriginalListName
                didFixUp = true
            }

            guard let listID = item.listID else {
                cleanedItems.append(sanitizedItem)
                continue
            }
            if listID == TodoList.trashID || listID == TodoList.completedID {
                cleanedItems.append(sanitizedItem)
                continue
            }
            if validListIDs.contains(listID) {
                cleanedItems.append(sanitizedItem)
                continue
            }
            didFixUp = true
            if cleanedLists.isEmpty {
                let inbox = TodoList(id: TodoList.inboxID, name: TodoList.inboxName)
                cleanedLists.append(inbox)
                validListIDs.insert(inbox.id)
            }
            if let fallbackListID = cleanedLists.first?.id {
                var copy = sanitizedItem
                copy.listID = fallbackListID
                cleanedItems.append(copy)
            }
        }

        return (cleanedLists, cleanedItems, didFixUp)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let appDir = appSupport.appendingPathComponent("FloatList")
        return appDir.appendingPathComponent("todos.json")
    }

    private static func normalizedTodoTitleInput(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxTodoTitleLength))
    }

    private static func normalizedListNameInput(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxListNameLength))
    }

    private static func normalizedListNameInput(_ raw: String, fallback: String) -> String {
        normalizedListNameInput(raw) ?? fallback
    }

    private static func clampedPersistedTodoTitle(_ raw: String) -> String {
        String(raw.prefix(maxTodoTitleLength))
    }

    private static func clampedPersistedListName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return String(raw.prefix(maxListNameLength))
    }

    // MARK: - Legacy store migration

    static let legacyStoreMigrationDefaultsKey = "floatlist.store.didMigrateLegacyStore"
    private static let legacyStoreMigrationMaxBytes: Int = 50 * 1024 * 1024

    @discardableResult
    private func migrateLegacyStoreIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard let legacyHome = Self.realHomeDirectory() else {
            defaults.set(true, forKey: Self.legacyStoreMigrationDefaultsKey)
            return false
        }
        let legacyURL = legacyHome.appendingPathComponent("Library/Application Support/FloatList/todos.json")
        return Self.performLegacyStoreMigration(
            legacyURL: legacyURL,
            targetURL: fileURL,
            fileManager: fileManager,
            defaults: defaults
        )
    }

    @discardableResult
    static func performLegacyStoreMigration(
        legacyURL: URL,
        targetURL: URL,
        fileManager: FileManager,
        defaults: UserDefaults
    ) -> Bool {
        if defaults.bool(forKey: legacyStoreMigrationDefaultsKey) {
            return false
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            defaults.set(true, forKey: legacyStoreMigrationDefaultsKey)
            return false
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: legacyURL.path)
        } catch {
            if Self.isMissingFileError(error) {
                defaults.set(true, forKey: legacyStoreMigrationDefaultsKey)
            } else {
                NSLog("FloatList legacy-store migration failed to stat legacy file: %@", String(describing: error))
            }
            return false
        }

        if let fileType = attributes[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
            defaults.set(true, forKey: legacyStoreMigrationDefaultsKey)
            return false
        }

        if let size = attributes[.size] as? NSNumber, size.intValue > legacyStoreMigrationMaxBytes {
            defaults.set(true, forKey: legacyStoreMigrationDefaultsKey)
            return false
        }

        do {
            let directoryURL = targetURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.copyItem(at: legacyURL, to: targetURL)
        } catch {
            NSLog("FloatList legacy-store migration failed: %@", String(describing: error))
            return false
        }

        defaults.set(true, forKey: legacyStoreMigrationDefaultsKey)
        return true
    }

    // `NSHomeDirectory()` resolves to the sandbox container, so the legacy
    // pre-sandbox path has to be reconstructed from the real passwd entry.
    private static func realHomeDirectory() -> URL? {
        guard let pw = getpwuid(getuid()) else { return nil }
        guard let cString = pw.pointee.pw_dir else { return nil }
        let path = String(cString: cString)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOENT) {
            return true
        }
        return false
    }
}
