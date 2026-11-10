import Darwin
import Foundation

@main
struct CleanHistoryTests {
    static func main() throws {
        try fixture { home, trash, log, _ in
            DispatchQueue.concurrentPerform(iterations: 100) { index in
                let store = CleanHistoryStore(logPath: log.logPath)
                do { try store.append(record("item-\(index)", "trash-\(index)")) } catch {
                    preconditionFailure("Concurrent append failed: \(error)")
                }
            }
            try check(log.read().count == 100)
            let original = home.appendingPathComponent("rollback")
            let moved = trash.appendingPathComponent("rollback")
            try Data("sentinel".utf8).write(to: moved)
            let failing = CleanHistoryStore(logPath: log.logPath, maximumBytes: 1)
            do {
                try failing.recordTrash(record(original.path, moved.path)) {
                    try FileManager().moveItem(at: moved, to: original)
                }
                preconditionFailure("Expected history failure")
            } catch CleanHistoryError.recordTooLarge {}
            try check(Data(contentsOf: original) == Data("sentinel".utf8))
            print("PASS concurrent independent stores retain all lines; failed audit restores fake trash")
        }
        try fixture { home, trash, log, restore in
            let source = trash.appendingPathComponent("item")
            let target = home.appendingPathComponent("item")
            try Data("saved".utf8).write(to: source)
            let entry = record(target.path, source.path)
            try log.append(entry)
            try restore.restore(entry)
            try check(Data(contentsOf: target) == Data("saved".utf8))
            try check(log.read().first?.status == .restored)
            print("PASS restore and audit")
        }
        try fixture { home, trash, _, restore in
            let source = trash.appendingPathComponent("item")
            let target = home.appendingPathComponent("item")
            try Data("trash".utf8).write(to: source)
            try Data("existing".utf8).write(to: target)
            try refuses(.destinationExists) { try restore.restore(record(target.path, source.path)) }
            try check(Data(contentsOf: target) == Data("existing".utf8))
            precondition(FileManager().fileExists(atPath: source.path))
            print("PASS exclusive rename preserves destination and source")
        }
        try fixture { home, trash, _, restore in
            let sentinel = home.deletingLastPathComponent().appendingPathComponent("sentinel")
            try Data("safe".utf8).write(to: sentinel)
            let source = trash.appendingPathComponent("item")
            try Data("trash".utf8).write(to: source)
            for path in [sentinel.path, home.path + "/../sentinel"] {
                try refuses(.invalidPath) { try restore.restore(record(path, source.path)) }
            }
            try refuses(.invalidPath) {
                try restore.restore(record(home.appendingPathComponent("item").path, sentinel.path))
            }
            try check(Data(contentsOf: sentinel) == Data("safe".utf8))
            let link = home.appendingPathComponent("link")
            try FileManager().createSymbolicLink(at: link, withDestinationURL: trash)
            try refuses(.parentMissing) {
                try restore.restore(record(link.appendingPathComponent("item").path, source.path))
            }
            print("PASS outside roots, traversal and symlink refused; sentinel survives")
        }
        try fixture { home, trash, log, restore in
            let target = home.appendingPathComponent("item")
            let source = trash.appendingPathComponent("gone")
            try refuses(.trashMissing) { try restore.restore(record(target.path, source.path)) }
            try Data().write(to: source)
            try refuses(.parentMissing) {
                try restore.restore(record(home.appendingPathComponent("gone/item").path, source.path))
            }
            try Data("malformed\n".utf8).write(to: log.logPath)
            try log.append(record(target.path, source.path))
            try check(log.read().count == 1)
            try check(Data(contentsOf: log.logPath).starts(with: Data("malformed\n".utf8)))
            let bounded = CleanHistoryStore(logPath: log.logPath, maximumBytes: 600)
            for index in 0..<20 {
                try bounded.append(record(target.path + String(index), source.path))
            }
            try check(Data(contentsOf: log.logPath).count <= 600)
            try check(bounded.read().first?.originalPath == target.path + "19")
            print("PASS missing paths, malformed line kept on disk, bounded log and newest first")
        }
    }

    static func record(_ original: String, _ trash: String) -> CleanHistoryEntry {
        CleanHistoryEntry(time: Date(timeIntervalSince1970: 10), mode: "clean", size: 5,
                          status: .trashed, originalPath: original, trashPath: trash)
    }

    static func check(_ condition: @autoclosure () throws -> Bool) throws {
        let result = try condition()
        precondition(result)
    }

    static func refuses(_ expected: CleanHistoryError, operation: () throws -> Void) throws {
        do {
            try operation()
            preconditionFailure("Expected refusal")
        } catch let error as CleanHistoryError { precondition(error == expected) }
    }

    static func fixture(_ test: (URL, URL, CleanHistoryStore, CleanHistoryRestore) throws -> Void) throws {
        guard let resolved = realpath(FileManager().temporaryDirectory.path, nil) else {
            throw CleanHistoryError.system(errno)
        }
        defer { free(resolved) }
        let root = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("fake-home")
        let trash = root.appendingPathComponent("fake-trash")
        try FileManager().createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager().createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? FileManager().removeItem(at: root) }
        let log = CleanHistoryStore(logPath: root.appendingPathComponent("history.jsonl"))
        let restore = CleanHistoryRestore(originalRoots: [home], trashRoots: [trash], log: log,
                                          now: { Date(timeIntervalSince1970: 20) })
        try test(home, trash, log, restore)
    }
}
