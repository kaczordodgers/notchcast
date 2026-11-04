// notchcast-sources: Tinycast/Features/Clean/Model/CleanSystem*.swift
// notchcast-sources: Tinycast/Features/Clean/CleanSystemRootClient.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootContract.swift notchcast/root/CleanSystem.swift
import Foundation
import Synchronization

@main struct SystemRootTest {
    static func main() async throws {
        let folder = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager().removeItem(at: folder) }
        let file = folder.appendingPathComponent("cache")
        try Data("test".utf8).write(to: file)
        let entry = try CleanSystem.inspect(file.path)
        let policy = CleanSystemPolicy(roots: [.init(path: folder.path, rule: .caches)],
            now: .now.addingTimeInterval(100), cacheAge: 1, logAge: 1)
        let moved = Mutex<[String]>([])
        let client = CleanSystemRootClient(run: { command, data in
            switch command {
            case .version: return Data("4\n".utf8)
            case .cleanSystemList: return try JSONEncoder().encode([entry])
            case .cleanSystemTrash:
                let reviewed = try JSONDecoder().decode(CleanSystemEntry.self, from: data)
                try CleanSystem.validate(reviewed, policy: policy)
                moved.withLock { $0.append(reviewed.path) }
                return Data("ok\n".utf8)
            default: fatalError()
            }
        }, policy: policy)
        let listed = try await client.list()
        precondition(listed == [entry])
        try await client.trash(listed[0])
        precondition(moved.withLock { $0 } == [entry.path])
        print("PASS: list → trash through fake root transport and helper validator")
        let outside = CleanSystemPolicy(roots: [], now: .now, cacheAge: 0, logAge: 0)
        do { try CleanSystem.validate(entry, policy: outside); fatalError() } catch CleanSystem.Failure.refused {}
        let refusing = CleanSystemRootClient(run: { _, _ in fatalError() }, policy: outside)
        do { try await refusing.trash(entry); fatalError() } catch CleanSystemRootClient.Failure.refused {}
        let link = folder.appendingPathComponent("link")
        try FileManager().createSymbolicLink(at: link, withDestinationURL: file)
        do { _ = try CleanSystem.inspect(link.path); fatalError() } catch CleanSystem.Failure.refused {}
        let directoryLink = folder.appendingPathComponent("escape")
        try FileManager().createSymbolicLink(at: directoryLink, withDestinationURL: folder)
        do {
            _ = try CleanSystem.inspect(directoryLink.path + "/cache")
            fatalError()
        } catch CleanSystem.Failure.refused {}
        do {
            _ = try CleanSystem.inspect(folder.path + "/../cache")
            fatalError()
        } catch CleanSystem.Failure.refused {}
        print("PASS: outside policy refused by client and helper; symlink escape refused")
        let old = CleanSystemRootClient(run: { _, _ in Data("3\n".utf8) }, policy: policy)
        do { _ = try await old.list(); fatalError() } catch CleanSystemRootClient.Failure.helperUpdate {}
        print("PASS: old helper requires helperUpdate")
    }
}
