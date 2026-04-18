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

    func testDeleteListCascadesTodosAndReselectsAnotherList() throws {
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
        XCTAssertEqual(store.items.map(\.title), ["Home A"])
        XCTAssertEqual(store.selectedListID, home.id)
    }

    func testDeleteLastListLeavesZeroListsAndNilSelection() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let only = store.addList(name: "Tasks")
        store.add(title: "Solo")

        store.deleteList(only)

        XCTAssertTrue(store.lists.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.selectedListID)
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
        store.moveTopLevel(from: 2, to: 0)

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

        store.moveTopLevel(from: 0, to: 2)

        XCTAssertEqual(store.visibleItems.map(\.title), ["B", "C", "A"])
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

    func testSetListIconRejectsEmpty() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let list = store.addList(name: "Work", icon: "🚀")

        store.setListIcon(list, to: "")
        XCTAssertEqual(store.lists.first?.icon, "🚀")

        store.setListIcon(list, to: "   \n\t  ")
        XCTAssertEqual(store.lists.first?.icon, "🚀")

        store.setListIcon(list, to: "🎯")
        XCTAssertEqual(store.lists.first?.icon, "🎯")
    }

    // MARK: - Subtasks

    func testDecodeV2FileWithoutParentIDKeyAssignsNil() throws {
        let fileURL = try makeStoreFileURL()
        let listID = UUID()
        let todoID = UUID()
        let ts = Date().timeIntervalSinceReferenceDate

        let json = """
        {
          "schemaVersion": 2,
          "lists": [{"id":"\(listID.uuidString)","name":"Work","icon":"\(TodoList.defaultIcon)","createdAt":\(ts)}],
          "todos": [{"id":"\(todoID.uuidString)","title":"Task","isCompleted":false,"listID":"\(listID.uuidString)","createdAt":\(ts)}],
          "selectedListID":"\(listID.uuidString)"
        }
        """
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.items.first?.parentID)
        XCTAssertEqual(store.items.first?.title, "Task")
        XCTAssertNil(store.recoveryNotice)
    }

    func testAddSubtaskStampsParentAndInheritsListID() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let list = store.addList(name: "Work")
        store.add(title: "Parent")
        let parent = try XCTUnwrap(store.items.first)

        store.addSubtask(title: "Child", parentID: parent.id)

        XCTAssertEqual(store.items.count, 2)
        let child = try XCTUnwrap(store.items.first(where: { $0.title == "Child" }))
        XCTAssertEqual(child.parentID, parent.id)
        XCTAssertEqual(child.listID, list.id)
    }

    func testTogglingParentCascadesToChildren() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Parent")
        let parent = try XCTUnwrap(store.items.first)
        store.addSubtask(title: "C1", parentID: parent.id)
        store.addSubtask(title: "C2", parentID: parent.id)

        store.toggle(parent)
        XCTAssertTrue(store.items.allSatisfy { $0.isCompleted })

        let refreshed = try XCTUnwrap(store.items.first(where: { $0.id == parent.id }))
        store.toggle(refreshed)
        XCTAssertTrue(store.items.allSatisfy { !$0.isCompleted })
    }

    func testCompletingLastChildCompletesParent() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Parent")
        let parent = try XCTUnwrap(store.items.first)
        store.addSubtask(title: "C1", parentID: parent.id)
        store.addSubtask(title: "C2", parentID: parent.id)

        let c1 = try XCTUnwrap(store.items.first(where: { $0.title == "C1" }))
        store.toggle(c1)
        XCTAssertFalse(try XCTUnwrap(store.items.first(where: { $0.id == parent.id })).isCompleted)

        let c2 = try XCTUnwrap(store.items.first(where: { $0.title == "C2" }))
        store.toggle(c2)
        XCTAssertTrue(try XCTUnwrap(store.items.first(where: { $0.id == parent.id })).isCompleted)
    }

    func testUncompletingAnyChildUncompletesParent() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Parent")
        let parent = try XCTUnwrap(store.items.first)
        store.addSubtask(title: "C1", parentID: parent.id)
        store.addSubtask(title: "C2", parentID: parent.id)
        store.toggle(parent)
        XCTAssertTrue(store.items.allSatisfy { $0.isCompleted })

        let c1 = try XCTUnwrap(store.items.first(where: { $0.title == "C1" }))
        store.toggle(c1)
        XCTAssertFalse(try XCTUnwrap(store.items.first(where: { $0.id == parent.id })).isCompleted)
    }

    func testAddingChildToCompleteParentUncompletesParent() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Parent")
        let parent = try XCTUnwrap(store.items.first)
        store.toggle(parent)
        XCTAssertTrue(try XCTUnwrap(store.items.first).isCompleted)

        store.addSubtask(title: "New", parentID: parent.id)

        XCTAssertFalse(try XCTUnwrap(store.items.first(where: { $0.id == parent.id })).isCompleted)
    }

    func testDeletingParentCascadesChildren() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Parent")
        let parent = try XCTUnwrap(store.items.first)
        store.addSubtask(title: "C1", parentID: parent.id)
        store.addSubtask(title: "C2", parentID: parent.id)
        store.add(title: "Other")

        store.delete(parent)

        XCTAssertEqual(store.items.map(\.title), ["Other"])
    }

    func testDeletingLastChildLeavesParentCompletionIndependent() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        _ = store.addList(name: "Work")
        store.add(title: "Parent")
        let parent = try XCTUnwrap(store.items.first)
        store.addSubtask(title: "OnlyChild", parentID: parent.id)

        let child = try XCTUnwrap(store.items.first(where: { $0.title == "OnlyChild" }))
        store.delete(child)

        XCTAssertEqual(store.items.map(\.title), ["Parent"])
        XCTAssertFalse(try XCTUnwrap(store.items.first).isCompleted)

        store.addSubtask(title: "Second", parentID: parent.id)
        let second = try XCTUnwrap(store.items.first(where: { $0.title == "Second" }))
        store.toggle(second)
        XCTAssertTrue(try XCTUnwrap(store.items.first(where: { $0.id == parent.id })).isCompleted)

        store.delete(try XCTUnwrap(store.items.first(where: { $0.title == "Second" })))
        XCTAssertTrue(try XCTUnwrap(store.items.first(where: { $0.id == parent.id })).isCompleted)
    }

    func testMoveChildStaysWithinSiblingsSlice() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let list = store.addList(name: "Work")
        store.add(title: "P1")
        let p1 = try XCTUnwrap(store.items.first)
        store.addSubtask(title: "C1a", parentID: p1.id)
        store.addSubtask(title: "C1b", parentID: p1.id)
        store.addSubtask(title: "C1c", parentID: p1.id)
        store.add(title: "P2")

        store.moveChild(parentID: p1.id, from: 2, to: 0)

        XCTAssertEqual(store.children(of: p1.id).map(\.title), ["C1c", "C1a", "C1b"])
        XCTAssertEqual(store.topLevelItems(in: list.id).map(\.title), ["P1", "P2"])
    }

    func testMoveParentCarriesChildrenAsContiguousBlock() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)
        let list = store.addList(name: "Work")
        store.add(title: "P1")
        store.add(title: "P2")
        store.add(title: "P3")

        let p2 = try XCTUnwrap(store.items.first(where: { $0.title == "P2" }))
        store.addSubtask(title: "C2a", parentID: p2.id)
        store.addSubtask(title: "C2b", parentID: p2.id)

        store.moveTopLevel(from: 1, to: 0)

        XCTAssertEqual(store.visibleItems.map(\.title), ["P2", "C2a", "C2b", "P1", "P3"])
        XCTAssertEqual(store.topLevelItems(in: list.id).map(\.title), ["P2", "P1", "P3"])
        XCTAssertEqual(store.children(of: p2.id).map(\.title), ["C2a", "C2b"])
    }

    func testSanitizeDropsOrphanedChildrenOnLoad() throws {
        let fileURL = try makeStoreFileURL()
        let listID = UUID()
        let otherListID = UUID()
        let parentID = UUID()
        let okChildID = UUID()
        let orphanChildID = UUID()
        let wrongListChildID = UUID()
        let ghostParentID = UUID()
        let ts = Date().timeIntervalSinceReferenceDate

        let json = """
        {
          "schemaVersion": 3,
          "lists": [
            {"id":"\(listID.uuidString)","name":"Work","icon":"\(TodoList.defaultIcon)","createdAt":\(ts)},
            {"id":"\(otherListID.uuidString)","name":"Other","icon":"\(TodoList.defaultIcon)","createdAt":\(ts)}
          ],
          "todos": [
            {"id":"\(parentID.uuidString)","title":"Parent","isCompleted":false,"listID":"\(listID.uuidString)","createdAt":\(ts)},
            {"id":"\(okChildID.uuidString)","title":"OK","isCompleted":false,"listID":"\(listID.uuidString)","parentID":"\(parentID.uuidString)","createdAt":\(ts)},
            {"id":"\(orphanChildID.uuidString)","title":"Orphan","isCompleted":false,"listID":"\(listID.uuidString)","parentID":"\(ghostParentID.uuidString)","createdAt":\(ts)},
            {"id":"\(wrongListChildID.uuidString)","title":"WrongList","isCompleted":false,"listID":"\(otherListID.uuidString)","parentID":"\(parentID.uuidString)","createdAt":\(ts)}
          ],
          "selectedListID":"\(listID.uuidString)"
        }
        """
        try Data(json.utf8).write(to: fileURL, options: .atomic)

        let store = TodoStore(fileURL: fileURL)

        XCTAssertEqual(Set(store.items.map(\.title)), ["Parent", "OK"])
        XCTAssertEqual(store.children(of: parentID).map(\.title), ["OK"])
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
