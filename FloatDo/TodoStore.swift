import Foundation
import Combine

struct TodoStoreRecoveryNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let backupURL: URL?
}

class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = []
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

    func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            items = []
            isStorageWritable = true
            recoveryNotice = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([TodoItem].self, from: data)
            isStorageWritable = true
            recoveryNotice = nil
        } catch {
            recoverUnreadableStore(after: error)
        }
    }

    func save() {
        guard isStorageWritable else { return }
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(TodoItem(title: trimmed))
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

    private func recoverUnreadableStore(after decodeError: Error) {
        let backupURL = makeBackupURL()

        do {
            try fileManager.moveItem(at: fileURL, to: backupURL)
            items = []
            isStorageWritable = true
            recoveryNotice = TodoStoreRecoveryNotice(
                message: "Your todo file was unreadable. A backup was saved and the list was reset.",
                backupURL: backupURL
            )
        } catch {
            items = []
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
