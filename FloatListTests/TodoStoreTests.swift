import XCTest
import AppKit
@testable import FloatList

@MainActor
final class TodoStoreTests: XCTestCase {
    func testLegacyJSONArrayIsRecoveredAsUnreadableStoreAndBackedUp() throws {
        let fileURL = try makeStoreFileURL()
        let expectedItem = TodoItem(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Ship recovery fix",
            isCompleted: false,
            createdAt: Date(timeIntervalSince1970: 1_717_171_717)
        )

        let data = try JSONEncoder().encode([expectedItem])
        try data.write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)
        let notice = try XCTUnwrap(store.recoveryNotice)
        let backupURL = try XCTUnwrap(notice.backupURL)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertEqual(store.selectedListID, TodoList.inboxID)
        XCTAssertTrue(notice.message.contains("backup was saved"))
        XCTAssertEqual(try Data(contentsOf: backupURL), data)
    }

    func testLoadSchemaV2FileRestoresListsAndSelection() throws {
        let fileURL = try makeStoreFileURL()
        let list = TodoList(name: "Work")
        let todo = TodoItem(title: "Write spec", listID: list.id)
        let file = TodoStoreFile(
            schemaVersion: TodoStore.currentSchemaVersion,
            lists: [list],
            todos: [todo],
            selectedListID: list.id
        )
        try JSONEncoder().encode(file).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertEqual(store.lists.map(\.name), ["Work"])
        XCTAssertEqual(store.items.map(\.title), ["Write spec"])
        XCTAssertEqual(store.selectedListID, list.id)
    }

    func testMissingFileStartsWithPrecreatedInboxAndNoRecoveryNotice() throws {
        let fileURL = try makeStoreFileURL()

        let store = TodoStore(fileURL: fileURL)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertEqual(store.lists.first?.name, TodoList.inboxName)
        XCTAssertEqual(store.selectedListID, TodoList.inboxID)
        XCTAssertNil(store.recoveryNotice)

        let persisted = try JSONDecoder().decode(TodoStoreFile.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(persisted.lists.map(\.id), [TodoList.inboxID])
        XCTAssertTrue(persisted.todos.isEmpty)
        XCTAssertEqual(persisted.selectedListID, TodoList.inboxID)
    }

    func testEmptyPersistedStoreIsNormalizedToInbox() throws {
        let fileURL = try makeStoreFileURL()
        let emptyFile = TodoStoreFile(
            schemaVersion: TodoStore.currentSchemaVersion,
            lists: [],
            todos: [],
            selectedListID: nil
        )
        try JSONEncoder().encode(emptyFile).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.selectedListID, TodoList.inboxID)

        let persisted = try JSONDecoder().decode(TodoStoreFile.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(persisted.lists.map(\.id), [TodoList.inboxID])
        XCTAssertEqual(persisted.selectedListID, TodoList.inboxID)
    }

    func testCorruptedJSONMovesUnreadableFileToBackupAndPrecreatesInbox() throws {
        let fileURL = try makeStoreFileURL()
        let corruptedContents = "{ definitely not json".data(using: .utf8)!
        try corruptedContents.write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)
        let notice = try XCTUnwrap(store.recoveryNotice)
        let backupURL = try XCTUnwrap(notice.backupURL)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertEqual(store.selectedListID, TodoList.inboxID)
        XCTAssertTrue(notice.message.contains("backup was saved"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptedContents)
    }

    func testSaveAfterRecoveryWritesCleanStoreWithoutDeletingBackup() throws {
        let fileURL = try makeStoreFileURL()
        let corruptedContents = "[] nope".data(using: .utf8)!
        try corruptedContents.write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)
        let backupURL = try XCTUnwrap(store.recoveryNotice?.backupURL)

        store.addList(name: "Tasks")
        store.add(title: "Recovered task")

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.save()
        let reloaded = try JSONDecoder().decode(TodoStoreFile.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(reloaded.todos.map(\.title), ["Recovered task"])
        XCTAssertEqual(reloaded.lists.map(\.name), [TodoList.inboxName, "Tasks"])
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptedContents)
    }

    func testWhitespaceOnlyTaskIsIgnored() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        store.addList(name: "Tasks")

        store.add(title: "   \n\t  ")

        XCTAssertTrue(store.items.isEmpty)
    }

    func testAddTodoClampsTitleLength() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        store.addList(name: "Tasks")
        let oversized = String(repeating: "A", count: TodoStore.maxTodoTitleLength + 25)

        store.add(title: oversized)

        XCTAssertEqual(store.items.first?.title.count, TodoStore.maxTodoTitleLength)
        XCTAssertEqual(store.items.first?.title, String(repeating: "A", count: TodoStore.maxTodoTitleLength))
    }

    func testAddTodoWithNoSelectedListIsIgnored() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        store.selectList(nil)

        store.add(title: "Orphan")

        XCTAssertTrue(store.items.isEmpty)
    }

    func testAddListAppendsAfterInboxAndSelectsNewList() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        let first = store.addList(name: "Work")
        let second = store.addList(name: "Home")

        XCTAssertEqual(store.lists.map(\.name), [TodoList.inboxName, "Work", "Home"])
        XCTAssertEqual(store.selectedListID, second.id)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testAddListClampsNameLength() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let oversized = String(repeating: "W", count: TodoStore.maxListNameLength + 12)

        let list = store.addList(name: oversized)

        XCTAssertEqual(list.name.count, TodoStore.maxListNameLength)
        XCTAssertEqual(store.lists.first(where: { $0.id == list.id })?.name.count, TodoStore.maxListNameLength)
    }

    func testAddTodoStampsSelectedListID() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let list = store.addList(name: "Work")

        store.add(title: "First")

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.listID, list.id)
        XCTAssertEqual(store.visibleItems.map(\.title), ["First"])
    }

    func testCompletingTodoRemovesItFromRegularVisibleItemsAndShowsItInCompletedItems() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let work = store.addList(name: "Work")
        store.add(title: "First")
        store.add(title: "Second")

        let first = try XCTUnwrap(store.items.first)
        store.toggle(first)

        XCTAssertEqual(store.visibleItems.map(\.title), ["Second"])
        XCTAssertEqual(store.completedItems(in: work.id).map(\.title), ["First"])
        XCTAssertEqual(store.items(in: work.id).map(\.title), ["Second", "First"])
    }

    func testSelectingCompletedShowsCompletedItemsAcrossLists() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Write spec")
        store.add(title: "Ship fix")

        let home = store.addList(name: "Home")
        store.add(title: "Buy milk")

        let workCompleted = store.items.first(where: { $0.title == "Ship fix" })!
        let homeCompleted = store.items.first(where: { $0.title == "Buy milk" })!
        store.toggle(workCompleted)
        store.toggle(homeCompleted)

        store.selectList(TodoList.completedID)

        XCTAssertTrue(store.isCompletedSelected)
        XCTAssertEqual(store.visibleItems.map(\.title), ["Ship fix", "Buy milk"])
        XCTAssertEqual(store.sourceListName(for: store.visibleItems[0]), "Work")
        XCTAssertEqual(store.sourceListName(for: store.visibleItems[1]), home.name)
    }

    func testDeleteTodoMovesItToTrashAndPreservesOriginalMetadata() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let work = store.addList(name: "Work")
        store.add(title: "First")

        let item = try XCTUnwrap(store.items.first)
        store.delete(item)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(try XCTUnwrap(store.items.first).isTrashed)
        XCTAssertEqual(store.items.first?.trashedOriginalListID, work.id)
        XCTAssertEqual(store.items.first?.trashedOriginalListName, "Work")
        XCTAssertNotNil(store.items.first?.trashedAt)
        XCTAssertTrue(store.visibleItems.isEmpty)

        store.selectList(TodoList.trashID)
        XCTAssertEqual(store.visibleItems.map(\.title), ["First"])
    }

    func testDeleteListMovesTodosToTrashAndReselectsAnotherList() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        let work = store.addList(name: "Work")
        store.add(title: "Work A")
        store.add(title: "Work B")

        let home = store.addList(name: "Home")
        store.add(title: "Home A")

        store.selectList(work.id)
        store.deleteList(work)

        XCTAssertEqual(store.lists.map(\.name), [TodoList.inboxName, "Home"])
        XCTAssertEqual(store.selectedListID, TodoList.inboxID)
        XCTAssertTrue(store.visibleItems.isEmpty)

        store.selectList(home.id)
        XCTAssertEqual(store.visibleItems.map(\.title), ["Home A"])

        store.selectList(TodoList.trashID)
        XCTAssertEqual(store.visibleItems.map(\.title), ["Work A", "Work B"])
        XCTAssertEqual(store.visibleItems.map(\.trashedOriginalListName), ["Work", "Work"])
    }

    func testDeleteLastListLeavesZeroRegularListsAndSelectsTrash() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let inbox = try XCTUnwrap(store.lists.first)
        let only = store.addList(name: "Tasks")
        store.add(title: "Solo")

        store.deleteList(only)
        store.deleteList(inbox)

        XCTAssertTrue(store.lists.isEmpty)
        XCTAssertEqual(store.selectedListID, TodoList.trashID)
        XCTAssertEqual(store.items.filter { $0.isTrashed }.map(\.title), ["Solo"])
    }

    func testMarkingCompletedItemIncompleteReturnsItToOriginalListVisibleItems() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let work = store.addList(name: "Work")
        store.add(title: "Recover me")

        let item = try XCTUnwrap(store.items.first)
        store.toggle(item)
        store.selectList(TodoList.completedID)

        let completed = try XCTUnwrap(store.visibleItems.first)
        store.toggle(completed)

        XCTAssertTrue(store.visibleItems.isEmpty)
        store.selectList(work.id)
        XCTAssertEqual(store.visibleItems.map(\.title), ["Recover me"])
        XCTAssertTrue(store.completedItems(in: work.id).isEmpty)
    }

    func testRenameListUpdatesName() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let list = store.addList(name: "Work")

        store.renameList(list, to: "Workshop")

        XCTAssertEqual(store.lists.first(where: { $0.id == list.id })?.name, "Workshop")
    }

    func testRenameTodoAndListClampLength() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let list = store.addList(name: "Work")
        store.add(title: "Short")
        let item = try XCTUnwrap(store.items.first)

        let longTitle = String(repeating: "T", count: TodoStore.maxTodoTitleLength + 10)
        let longName = String(repeating: "L", count: TodoStore.maxListNameLength + 10)

        store.rename(item, to: longTitle)
        store.renameList(list, to: longName)

        XCTAssertEqual(store.items.first?.title.count, TodoStore.maxTodoTitleLength)
        XCTAssertEqual(store.lists.first(where: { $0.id == list.id })?.name.count, TodoStore.maxListNameLength)
    }

    func testMoveTodoWithinFilteredListPreservesOtherLists() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        let work = store.addList(name: "Work")
        store.add(title: "W1")
        store.add(title: "W2")
        store.add(title: "W3")

        let home = store.addList(name: "Home")
        store.add(title: "H1")
        store.add(title: "H2")

        store.selectList(work.id)
        store.move(from: 2, to: 0)

        XCTAssertEqual(store.visibleItems.map(\.title), ["W3", "W1", "W2"])

        store.selectList(home.id)
        XCTAssertEqual(store.visibleItems.map(\.title), ["H1", "H2"])
    }

    func testMoveTodoDownWithinFilteredList() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        _ = store.addList(name: "Work")
        store.add(title: "A")
        store.add(title: "B")
        store.add(title: "C")

        store.move(from: 0, to: 2)

        XCTAssertEqual(store.visibleItems.map(\.title), ["B", "C", "A"])
    }

    func testMoveTodoSkipsCompletedItemsAndKeepsCompletedTailStable() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        let work = store.addList(name: "Work")
        store.add(title: "A")
        store.add(title: "B")
        store.add(title: "C")

        let completed = try XCTUnwrap(store.items.last)
        store.toggle(completed)
        store.move(from: 0, to: 1)

        XCTAssertEqual(store.visibleItems.map(\.title), ["B", "A"])
        XCTAssertEqual(store.completedItems(in: work.id).map(\.title), ["C"])
        XCTAssertEqual(store.items(in: work.id).map(\.title), ["B", "A", "C"])
    }

    func testRestoreReturnsTodoToExistingOriginalList() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let work = store.addList(name: "Work")
        store.add(title: "Recover me")
        let item = try XCTUnwrap(store.items.first)
        store.moveToTrash(item)

        store.selectList(TodoList.trashID)
        let trashedItem = try XCTUnwrap(store.visibleItems.first)
        store.restore(trashedItem)

        XCTAssertEqual(store.selectedListID, TodoList.trashID)
        XCTAssertEqual(store.items.first?.listID, work.id)
        XCTAssertNil(store.items.first?.trashedAt)
        XCTAssertNil(store.items.first?.trashedOriginalListID)
        XCTAssertNil(store.items.first?.trashedOriginalListName)
    }

    func testDeletingCompletedTodoMovesItToTrashAndPreservesOriginalMetadata() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let work = store.addList(name: "Work")
        store.add(title: "Done already")

        let item = try XCTUnwrap(store.items.first)
        store.toggle(item)

        let completed = try XCTUnwrap(store.completedItems(in: work.id).first)
        store.delete(completed)

        XCTAssertEqual(store.completedItems(in: work.id).count, 0)
        XCTAssertEqual(store.items.filter(\.isTrashed).map(\.title), ["Done already"])
        XCTAssertEqual(store.items.first?.trashedOriginalListID, work.id)
        XCTAssertTrue(try XCTUnwrap(store.items.first).isCompleted)
    }

    func testRestoringCompletedTodoFromTrashKeepsItCompleted() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let work = store.addList(name: "Work")
        store.add(title: "Saved for later")

        let item = try XCTUnwrap(store.items.first)
        store.toggle(item)
        store.moveToTrash(try XCTUnwrap(store.items.first))

        store.selectList(TodoList.trashID)
        let trashed = try XCTUnwrap(store.visibleItems.first)
        store.restore(trashed)

        XCTAssertEqual(store.selectedListID, TodoList.trashID)
        XCTAssertEqual(store.items.first?.listID, work.id)
        XCTAssertTrue(try XCTUnwrap(store.items.first).isCompleted)
        XCTAssertEqual(store.completedItems(in: work.id).map(\.title), ["Saved for later"])
    }

    func testRestoreRecreatesOriginalListWhenItWasDeleted() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let work = store.addList(name: "Work")
        store.add(title: "Bring back")

        store.deleteList(work)
        store.selectList(TodoList.trashID)
        let trashedItem = try XCTUnwrap(store.visibleItems.first)
        store.restore(trashedItem)

        let restoredList = try XCTUnwrap(store.lists.last)
        XCTAssertEqual(restoredList.name, "Work")
        XCTAssertEqual(store.items.first?.listID, restoredList.id)
        XCTAssertEqual(store.items.first?.title, "Bring back")
    }

    func testPermanentlyDeleteRemovesTrashedItemFromStorage() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Trash me")
        let item = try XCTUnwrap(store.items.first)
        store.moveToTrash(item)

        let trashedItem = try XCTUnwrap(store.items.first)
        store.permanentlyDelete(trashedItem)

        XCTAssertTrue(store.items.isEmpty)
    }

    func testEmptyTrashOnlyRemovesTrashedItems() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Keep")
        store.add(title: "Discard")

        let discard = try XCTUnwrap(store.items.last)
        store.moveToTrash(discard)
        store.emptyTrash()

        XCTAssertEqual(store.items.map(\.title), ["Keep"])
        XCTAssertFalse(store.items.contains(where: \.isTrashed))
    }

    func testSchemaV3FileLoadsWithoutTrashMetadata() throws {
        let fileURL = try makeStoreFileURL()
        let list = TodoList(name: "Work")
        let todo = TodoItem(title: "Legacy task", listID: list.id)
        let payload = """
        {
          "schemaVersion": 3,
          "lists": [{"id":"\(list.id.uuidString)","name":"Work","icon":"\(list.icon)","createdAt":\(list.createdAt.timeIntervalSinceReferenceDate)}],
          "todos": [{"id":"\(todo.id.uuidString)","title":"Legacy task","isCompleted":false,"listID":"\(list.id.uuidString)","createdAt":\(todo.createdAt.timeIntervalSinceReferenceDate)}],
          "selectedListID":"\(list.id.uuidString)"
        }
        """
        try Data(payload.utf8).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertEqual(store.visibleItems.map(\.title), ["Legacy task"])
        XCTAssertNil(store.items.first?.trashedAt)
        XCTAssertNil(store.items.first?.trashedOriginalListID)
        XCTAssertNil(store.items.first?.trashedOriginalListName)
    }

    func testSchemaV4RoundTripsTrashMetadata() throws {
        let fileURL = try makeStoreFileURL()
        let trashed = TodoItem(
            title: "Recovered later",
            isCompleted: true,
            listID: TodoList.trashID,
            trashedAt: Date(timeIntervalSince1970: 1_800_000_000),
            trashedOriginalListID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            trashedOriginalListName: "Work"
        )
        let file = TodoStoreFile(
            schemaVersion: TodoStore.currentSchemaVersion,
            lists: [],
            todos: [trashed],
            selectedListID: TodoList.trashID
        )
        try JSONEncoder().encode(file).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)
        let restoredFile = try JSONDecoder().decode(TodoStoreFile.self, from: Data(contentsOf: fileURL))

        XCTAssertEqual(store.selectedListID, TodoList.trashID)
        XCTAssertEqual(store.visibleItems.map(\.title), ["Recovered later"])
        XCTAssertEqual(restoredFile.todos.first?.trashedOriginalListName, "Work")
        XCTAssertEqual(restoredFile.todos.first?.trashedOriginalListID, trashed.trashedOriginalListID)
        XCTAssertEqual(restoredFile.todos.first?.trashedAt, trashed.trashedAt)
    }

    func testFutureSchemaLeavesFileUntouchedAndPausesSaving() throws {
        let fileURL = try makeStoreFileURL()
        let list = TodoList(name: "Work")
        let todo = TodoItem(title: "Keep me", listID: list.id)
        let file = TodoStoreFile(
            schemaVersion: TodoStore.currentSchemaVersion + 1,
            lists: [list],
            todos: [todo],
            selectedListID: list.id
        )
        let originalData = try JSONEncoder().encode(file)
        try originalData.write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertTrue(store.lists.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.selectedListID)
        XCTAssertNotNil(store.recoveryNotice)
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)

        _ = store.addList(name: "Should not save")
        store.add(title: "Also should not save")
        XCTAssertTrue(store.lists.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.selectedListID)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }

    func testLoadRehomesOrphanedItemsAndRecreatesInbox() throws {
        let fileURL = try makeStoreFileURL()
        let missingListID = UUID()
        let orphaned = TodoItem(title: "Orphaned", listID: missingListID)
        let file = TodoStoreFile(
            schemaVersion: TodoStore.currentSchemaVersion,
            lists: [],
            todos: [orphaned],
            selectedListID: missingListID
        )
        try JSONEncoder().encode(file).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertEqual(store.items.map(\.listID), [TodoList.inboxID])
        XCTAssertEqual(store.selectedListID, TodoList.inboxID)
        XCTAssertNotNil(store.recoveryNotice)
    }

    func testLoadClampsPersistedTodoAndListLengths() throws {
        let fileURL = try makeStoreFileURL()
        let oversizedListName = String(repeating: "L", count: TodoStore.maxListNameLength + 20)
        let oversizedTitle = String(repeating: "T", count: TodoStore.maxTodoTitleLength + 20)
        let list = TodoList(name: oversizedListName)
        let todo = TodoItem(
            title: oversizedTitle,
            listID: list.id,
            trashedOriginalListName: oversizedListName
        )
        let file = TodoStoreFile(
            schemaVersion: TodoStore.currentSchemaVersion,
            lists: [list],
            todos: [todo],
            selectedListID: list.id
        )
        try JSONEncoder().encode(file).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertEqual(store.lists.first?.name.count, TodoStore.maxListNameLength)
        XCTAssertEqual(store.items.first?.title.count, TodoStore.maxTodoTitleLength)
        XCTAssertEqual(store.items.first?.trashedOriginalListName?.count, TodoStore.maxListNameLength)
        XCTAssertNotNil(store.recoveryNotice)
    }

    func testSelectingTrashShowsOnlyTrashedItems() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "A")
        store.add(title: "B")

        let trashed = try XCTUnwrap(store.items.last)
        store.moveToTrash(trashed)

        store.selectList(TodoList.trashID)

        XCTAssertEqual(store.visibleItems.map(\.title), ["B"])
    }

    func testCompletedViewExcludesTrashedCompletedItems() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Done")

        let item = try XCTUnwrap(store.items.first)
        store.toggle(item)
        store.moveToTrash(try XCTUnwrap(store.items.first))

        store.selectList(TodoList.completedID)
        XCTAssertTrue(store.visibleItems.isEmpty)

        store.selectList(TodoList.trashID)
        XCTAssertEqual(store.visibleItems.map(\.title), ["Done"])
    }

    func testCompletedSelectionRoundTripsThroughSaveAndLoad() throws {
        let fileURL = try makeStoreFileURL()
        let list = TodoList(name: "Work")
        let todo = TodoItem(title: "Finished", isCompleted: true, listID: list.id)
        let file = TodoStoreFile(
            schemaVersion: TodoStore.currentSchemaVersion,
            lists: [list],
            todos: [todo],
            selectedListID: TodoList.completedID
        )
        try JSONEncoder().encode(file).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)
        let restoredFile = try JSONDecoder().decode(TodoStoreFile.self, from: Data(contentsOf: fileURL))

        XCTAssertEqual(store.selectedListID, TodoList.completedID)
        XCTAssertEqual(store.visibleItems.map(\.title), ["Finished"])
        XCTAssertEqual(restoredFile.selectedListID, TodoList.completedID)
    }

    func testDecodeListWithMissingIconUsesDefault() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let ts = createdAt.timeIntervalSinceReferenceDate

        let payloads = [
            #"{"id":"\#(id.uuidString)","name":"Work","createdAt":\#(ts)}"#,
            #"{"id":"\#(id.uuidString)","name":"Work","icon":"","createdAt":\#(ts)}"#,
            #"{"id":"\#(id.uuidString)","name":"Work","icon":"   \t  ","createdAt":\#(ts)}"#
        ]

        for json in payloads {
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(TodoList.self, from: data)
            XCTAssertEqual(decoded.icon, TodoList.defaultIcon)
            XCTAssertEqual(decoded.name, "Work")
            XCTAssertEqual(decoded.id, id)
        }
    }

    func testDecodeListRejectsLegacyEmojiIcon() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 700_000_001)
        let json = #"{"id":"\#(id.uuidString)","name":"Work","icon":"📝","createdAt":\#(createdAt.timeIntervalSinceReferenceDate)}"#

        let decoded = try JSONDecoder().decode(TodoList.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.icon, TodoList.defaultIcon)
    }

    func testDecodeListKeepsSymbolLikeIconWithoutAppKitValidation() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 700_000_002)
        let payloads = [
            #"{"id":"\#(id.uuidString)","name":"Work","icon":"target","createdAt":\#(createdAt.timeIntervalSinceReferenceDate)}"#,
            #"{"id":"\#(id.uuidString)","name":"Work","icon":"checkmark.circle.fill","createdAt":\#(createdAt.timeIntervalSinceReferenceDate)}"#
        ]
        let expectedIcons = ["target", "checkmark.circle.fill"]

        for (json, expectedIcon) in zip(payloads, expectedIcons) {
            let decoded = try JSONDecoder().decode(TodoList.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.icon, expectedIcon)
        }
    }

    func testMoveListReordersLists() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "A")
        _ = store.addList(name: "B")
        _ = store.addList(name: "C")

        // [Inbox, A, B, C] — move A down past C.
        store.moveList(from: 1, to: 3)
        XCTAssertEqual(store.lists.map(\.name), [TodoList.inboxName, "B", "C", "A"])

        store.moveList(from: 3, to: 1)
        XCTAssertEqual(store.lists.map(\.name), [TodoList.inboxName, "A", "B", "C"])
    }

    func testMoveListWithInvalidIndicesIsNoop() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "A")
        _ = store.addList(name: "B")
        let originalOrder = store.lists.map(\.name)

        store.moveList(from: 0, to: 0)
        XCTAssertEqual(store.lists.map(\.name), originalOrder)

        store.moveList(from: 5, to: 0)
        XCTAssertEqual(store.lists.map(\.name), originalOrder)

        store.moveList(from: 0, to: 5)
        XCTAssertEqual(store.lists.map(\.name), originalOrder)

        store.moveList(from: -1, to: 0)
        XCTAssertEqual(store.lists.map(\.name), originalOrder)
    }

    func testSetListIconRejectsInvalidValues() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let list = store.addList(name: "Work", icon: "star")
        let lookup = { store.lists.first(where: { $0.id == list.id })?.icon }

        store.setListIcon(list, to: "")
        XCTAssertEqual(lookup(), "star")

        store.setListIcon(list, to: "   \n\t  ")
        XCTAssertEqual(lookup(), "star")

        // Non-SF-Symbol values (e.g. legacy emoji) are rejected.
        store.setListIcon(list, to: "🎯")
        XCTAssertEqual(lookup(), "star")

        store.setListIcon(list, to: "target")
        XCTAssertEqual(lookup(), "target")
    }

    func testTodoListSanitizesLegacyEmojiIconToDefault() throws {
        let list = TodoList(name: "Old", icon: "📝")
        XCTAssertEqual(list.icon, TodoList.defaultIcon)
    }

    // MARK: - Migration

    func testLoadDropsLegacyParentIDKeyAndKeepsItemsAsFlatTasks() throws {
        let fileURL = try makeStoreFileURL()
        let listID = UUID()
        let parentID = UUID()
        let childID = UUID()
        let ts = Date().timeIntervalSinceReferenceDate

        let json = """
        {
          "schemaVersion": 3,
          "lists": [{"id":"\(listID.uuidString)","name":"Work","icon":"\(TodoList.defaultIcon)","createdAt":\(ts)}],
          "todos": [
            {"id":"\(parentID.uuidString)","title":"Parent","isCompleted":false,"listID":"\(listID.uuidString)","createdAt":\(ts)},
            {"id":"\(childID.uuidString)","title":"Child","isCompleted":false,"listID":"\(listID.uuidString)","parentID":"\(parentID.uuidString)","createdAt":\(ts)}
          ],
          "selectedListID":"\(listID.uuidString)"
        }
        """
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertEqual(store.items.map(\.title), ["Parent", "Child"])
        XCTAssertTrue(store.items.allSatisfy { $0.listID == listID })
    }

    // MARK: - Undo

    func testUndoStartsDisabledAndBecomesEnabledAfterMutation() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        XCTAssertFalse(store.canUndo)

        store.addList(name: "Work")
        XCTAssertTrue(store.canUndo)
    }

    func testUndoRevertsAddItem() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        let list = store.addList(name: "Work")
        store.selectList(list.id)
        store.add(title: "Ship it")

        XCTAssertEqual(store.items.map(\.title), ["Ship it"])

        store.undo()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.canUndo) // addList snapshot still on stack

        store.undo()
        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertFalse(store.canUndo)
    }

    func testUndoRevertsRenameRestoresOriginalTitle() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        let list = store.addList(name: "Work")
        store.selectList(list.id)
        store.add(title: "Draft")
        let item = try XCTUnwrap(store.items.first)

        store.rename(item, to: "Final")
        XCTAssertEqual(store.items.first?.title, "Final")

        store.undo()
        XCTAssertEqual(store.items.first?.title, "Draft")
    }

    func testUndoRevertsMoveToTrash() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        let list = store.addList(name: "Work")
        store.selectList(list.id)
        store.add(title: "Temp")
        let item = try XCTUnwrap(store.items.first)

        store.moveToTrash(item)
        XCTAssertTrue(store.items.first?.isTrashed ?? false)

        store.undo()
        XCTAssertFalse(store.items.first?.isTrashed ?? true)
        XCTAssertEqual(store.items.first?.listID, list.id)
    }

    func testUndoRevertsDeleteListAndRestoresTrashedItems() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        let list = store.addList(name: "Work")
        store.selectList(list.id)
        store.add(title: "A")
        store.add(title: "B")

        store.deleteList(list)
        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertTrue(store.items.allSatisfy(\.isTrashed))

        store.undo()
        XCTAssertEqual(store.lists.map(\.name), [TodoList.inboxName, "Work"])
        XCTAssertFalse(store.items.contains(where: \.isTrashed))
        XCTAssertEqual(store.items.map(\.title).sorted(), ["A", "B"])
    }

    func testUndoStackIsCappedAtFiftyEntries() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        let list = store.addList(name: "Work")
        store.selectList(list.id)

        for i in 0..<60 {
            store.add(title: "Task \(i)")
        }

        var undoCount = 0
        while store.canUndo {
            store.undo()
            undoCount += 1
            if undoCount > 60 { break }
        }

        // 50-cap: earliest snapshots (including addList + first 9 adds) were evicted.
        XCTAssertEqual(undoCount, 50)
        XCTAssertFalse(store.canUndo)
        // 10 earliest tasks remain because their pre-mutation snapshots fell off the stack.
        XCTAssertEqual(store.items.count, 10)
    }

    // MARK: - Precreated Inbox first-run flow

    func testFirstTaskGoesIntoPrecreatedInboxAsNormalAdd() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        XCTAssertEqual(store.selectedListID, TodoList.inboxID)

        store.add(title: "Buy milk")

        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertEqual(store.items.map(\.title), ["Buy milk"])
        XCTAssertEqual(store.items.first?.listID, TodoList.inboxID)

        store.save()
        let persisted = try JSONDecoder().decode(TodoStoreFile.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(persisted.lists.map(\.id), [TodoList.inboxID])
        XCTAssertEqual(persisted.todos.map(\.title), ["Buy milk"])
        XCTAssertEqual(persisted.selectedListID, TodoList.inboxID)
        XCTAssertEqual(persisted.todos.first?.listID, TodoList.inboxID)
    }

    func testUndoAfterFirstTaskKeepsInboxAndRemovesOnlyTheTask() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        XCTAssertFalse(store.canUndo)

        store.add(title: "Buy milk")
        XCTAssertTrue(store.canUndo)

        store.undo()

        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.selectedListID, TodoList.inboxID)
        XCTAssertFalse(store.canUndo)
    }

    func testInboxReturnsAfterReloadingPersistedFile() throws {
        let fileURL = try makeStoreFileURL()
        _ = TodoStore(fileURL: fileURL)

        let reopened = TodoStore(fileURL: fileURL)

        XCTAssertEqual(reopened.lists.map(\.id), [TodoList.inboxID])
        XCTAssertEqual(reopened.selectedListID, TodoList.inboxID)
        XCTAssertTrue(reopened.items.isEmpty)
    }

    func testPendingSaveIsFlushedWhenAppResignsActive() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        store.add(title: "Ship before rebuild")

        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)

        let reopened = TodoStore(fileURL: fileURL)
        XCTAssertEqual(reopened.items.map(\.title), ["Ship before rebuild"])
        XCTAssertEqual(reopened.items.first?.listID, TodoList.inboxID)
    }

    func testSelectListDoesNotPolluteUndoStack() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        let a = store.addList(name: "A")
        let b = store.addList(name: "B")
        store.selectList(a.id)
        store.selectList(b.id)
        store.selectList(a.id)

        // addList snapshots pushed; selectList did not.
        // Undoing once should pop the most recent addList snapshot.
        store.undo()
        XCTAssertEqual(store.lists.map(\.name), [TodoList.inboxName, "A"])
        store.undo()
        XCTAssertEqual(store.lists.map(\.id), [TodoList.inboxID])
        XCTAssertFalse(store.canUndo)
    }

    func testToggleManyUndoRestoresBatchInOneStep() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        _ = store.addList(name: "Work")
        store.add(title: "A")
        store.add(title: "B")
        store.add(title: "C")

        store.toggleMany(Array(store.items.prefix(2)))

        XCTAssertEqual(store.items.map(\.title), ["C", "A", "B"])
        XCTAssertEqual(store.items.map(\.isCompleted), [false, true, true])

        store.undo()

        XCTAssertEqual(store.items.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(store.items.map(\.isCompleted), [false, false, false])
    }

    func testMoveItemsUndoRestoresBatchInOneStep() throws {
        let store = TodoStore(fileURL: try makeStoreFileURL())
        let source = store.addList(name: "Source")
        store.add(title: "A")
        store.add(title: "B")
        let target = store.addList(name: "Target")
        store.add(title: "T")

        let moving = store.items.filter { $0.listID == source.id }
        store.moveItems(moving, to: target.id)

        XCTAssertEqual(store.items(in: target.id).map(\.title), ["T", "A", "B"])

        store.undo()

        XCTAssertEqual(store.items(in: source.id).map(\.title), ["A", "B"])
        XCTAssertEqual(store.items(in: target.id).map(\.title), ["T"])
    }

    private func makeStoreFileURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatListTests-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("todos.json")
    }
}
