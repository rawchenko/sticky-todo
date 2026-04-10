import XCTest
@testable import FloatDo

final class TodoStoreTests: XCTestCase {
    func testLoadWithValidJSONRestoresItemsWithoutRecoveryNotice() throws {
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
        XCTAssertEqual(store.items.first?.isCompleted, expectedItem.isCompleted)
        XCTAssertNil(store.recoveryNotice)
    }

    func testMissingFileStartsEmptyWithoutRecoveryNotice() throws {
        let fileURL = try makeStoreFileURL()

        let store = TodoStore(fileURL: fileURL)

        XCTAssertTrue(store.items.isEmpty)
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

        store.add(title: "Recovered task")

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let reloadedItems = try JSONDecoder().decode([TodoItem].self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(reloadedItems.map(\.title), ["Recovered task"])
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptedContents)
    }

    func testWhitespaceOnlyTaskIsIgnored() throws {
        let fileURL = try makeStoreFileURL()
        let store = TodoStore(fileURL: fileURL)

        store.add(title: "   \n\t  ")

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
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
