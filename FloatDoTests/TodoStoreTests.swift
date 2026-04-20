import XCTest
@testable import FloatDo

final class TodoStoreTests: XCTestCase {
    func testLoadLegacyJSONMigratesToDefaultTasksListAndRewritesFile() throws {
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

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.id, expectedItem.id)
        XCTAssertEqual(store.items.first?.title, expectedItem.title)
        XCTAssertEqual(store.lists.count, 1)
        XCTAssertEqual(store.lists.first?.name, "Tasks")
        XCTAssertEqual(store.items.first?.listID, store.lists.first?.id)
        XCTAssertEqual(store.selectedListID, store.lists.first?.id)
        XCTAssertNil(store.recoveryNotice)

        let reloaded = try JSONDecoder().decode(TodoStoreFile.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(reloaded.schemaVersion, TodoStore.currentSchemaVersion)
        XCTAssertEqual(reloaded.lists.map(\.name), ["Tasks"])
        XCTAssertEqual(reloaded.todos.map(\.title), ["Ship recovery fix"])
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

    func testMissingFileStartsEmptyWithoutRecoveryNotice() throws {
        let fileURL = try makeStoreFileURL()

        let store = TodoStore(fileURL: fileURL)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.lists.isEmpty)
        XCTAssertNil(store.selectedListID)
        XCTAssertNil(store.recoveryNotice)
    }

    func testCorruptedJSONMovesUnreadableFileToBackupAndClearsItems() throws {
        let fileURL = try makeStoreFileURL()
        let corruptedContents = "{ definitely not json".data(using: .utf8)!
        try corruptedContents.write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)
        let notice = try XCTUnwrap(store.recoveryNotice)
        let backupURL = try XCTUnwrap(notice.backupURL)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.lists.isEmpty)
        XCTAssertNil(store.selectedListID)
        XCTAssertTrue(notice.message.contains("backup was saved"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
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

        let reloaded = try JSONDecoder().decode(TodoStoreFile.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(reloaded.todos.map(\.title), ["Recovered task"])
        XCTAssertEqual(reloaded.lists.map(\.name), ["Tasks"])
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptedContents)
    }

    func testWhitespaceOnlyTaskIsIgnored() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        store.addList(name: "Tasks")

        store.add(title: "   \n\t  ")

        XCTAssertTrue(store.items.isEmpty)
    }

    func testAddTodoWithNoSelectedListIsIgnored() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        store.add(title: "Orphan")

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testAddListAppendsAndSelectsNewList() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        let first = store.addList(name: "Work")
        let second = store.addList(name: "Home")

        XCTAssertEqual(store.lists.map(\.name), ["Work", "Home"])
        XCTAssertEqual(store.selectedListID, second.id)
        XCTAssertNotEqual(first.id, second.id)
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

        XCTAssertEqual(store.lists.map(\.name), ["Home"])
        XCTAssertEqual(store.selectedListID, home.id)
        XCTAssertEqual(store.visibleItems.map(\.title), ["Home A"])

        store.selectList(TodoList.trashID)
        XCTAssertEqual(store.visibleItems.map(\.title), ["Work A", "Work B"])
        XCTAssertEqual(store.visibleItems.map(\.trashedOriginalListName), ["Work", "Work"])
    }

    func testDeleteLastListLeavesZeroRegularListsAndSelectsTrash() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let only = store.addList(name: "Tasks")
        store.add(title: "Solo")

        store.deleteList(only)

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

        XCTAssertEqual(store.lists.first?.name, "Workshop")
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

        XCTAssertEqual(store.lists.map(\.name), ["Work"])
        XCTAssertEqual(store.items.first?.listID, store.lists.first?.id)
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

    func testMoveListReordersLists() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "A")
        _ = store.addList(name: "B")
        _ = store.addList(name: "C")

        store.moveList(from: 0, to: 2)
        XCTAssertEqual(store.lists.map(\.name), ["B", "C", "A"])

        store.moveList(from: 2, to: 0)
        XCTAssertEqual(store.lists.map(\.name), ["A", "B", "C"])
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

        store.setListIcon(list, to: "")
        XCTAssertEqual(store.lists.first?.icon, "star")

        store.setListIcon(list, to: "   \n\t  ")
        XCTAssertEqual(store.lists.first?.icon, "star")

        // Non-SF-Symbol values (e.g. legacy emoji) are rejected.
        store.setListIcon(list, to: "🎯")
        XCTAssertEqual(store.lists.first?.icon, "star")

        store.setListIcon(list, to: "target")
        XCTAssertEqual(store.lists.first?.icon, "target")
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

    private func makeStoreFileURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatDoTests-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("todos.json")
    }
}
