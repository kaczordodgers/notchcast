// notchcast-sources: Tinycast/Features/Clean/Model/CleanSystem*.swift
// notchcast-sources: Tinycast/Features/Clean/CleanSystemRootClient.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootContract.swift notchcast/root/CleanSystem.swift
import Foundation
import Synchronization
import Darwin

@main struct SystemRootTest {
    static func main() async throws {
        precondition(getuid() != 0)
        for (mode, uid, gid, accepted) in [(0o1777, 0, 80, true), (0o770, 0, 80, true),
                                          (0o777, 0, 80, false), (0o770, 501, 80, false),
                                          (0o770, 0, 250, true), (0o772, 0, 250, false),
                                          (0o775, 0, 20, false)] {
            var info = stat()
            info.st_mode = mode_t(mode)
            info.st_uid = uid_t(uid)
            info.st_gid = gid_t(gid)
            precondition(CleanSystem.acceptsParent(info, owner: uid_t(uid)) == accepted)
        }
        print("PASS: root sticky and admin parents accepted; unsafe modes and owners refused")
        let folder = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager().removeItem(at: folder) }
        let file = folder.appendingPathComponent("cache")
        try Data("test".utf8).write(to: file)
        let entry = try CleanSystem.inspect(file.path)
        var snapshot = stat()
        precondition(lstat(file.path, &snapshot) == 0)
        precondition(CleanSystem.matches(snapshot, entry: entry, owner: getuid()))
        precondition(!CleanSystem.matches(snapshot, entry: entry, owner: getuid() + 1))
        var replaced = snapshot
        replaced.st_ino += 1
        precondition(!CleanSystem.matches(replaced, entry: entry, owner: getuid()))
        replaced = snapshot
        replaced.st_mode = S_IFLNK
        precondition(!CleanSystem.matches(replaced, entry: entry, owner: getuid()))
        replaced = snapshot
        replaced.st_size += 1
        precondition(!CleanSystem.matches(replaced, entry: entry, owner: getuid()))
        replaced = snapshot
        replaced.st_mtimespec.tv_sec += 1
        precondition(!CleanSystem.matches(replaced, entry: entry, owner: getuid()))
        replaced = snapshot
        replaced.st_nlink += 1
        precondition(!CleanSystem.matches(replaced, entry: entry, owner: getuid()))
        print("PASS: handle snapshot rejects changed owner, inode, type, size, mtime and hard links")
        do {
            _ = try CleanSystem.inspect(file.path, owner: 0)
            fatalError("Non-root entry accepted")
        } catch CleanSystem.Failure.refused {}
        print("PASS: system entry owned by non-root refused")
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
        let version = Mutex("3")
        let updating = CleanSystemRootClient(run: { command, _ in
            if command == .version { return Data((version.withLock { $0 } + "\n").utf8) }
            return try JSONEncoder().encode([entry])
        }, policy: policy)
        do { _ = try await updating.list(); fatalError() } catch CleanSystemRootClient.Failure.helperUpdate {}
        version.withLock { $0 = RootContract.version }
        let updated = try await updating.list()
        precondition(updated == [entry])
        let invalidUTF8 = CleanSystemRootClient(run: { command, _ in
            command == .version ? Data((RootContract.version + "\n").utf8) : Data([0xff])
        }, policy: policy)
        do { _ = try await invalidUTF8.list(); fatalError() } catch CleanSystemRootClient.Failure.invalidResponse {}
        print("PASS: Scan detects a helper upgrade; non-UTF-8 reply refused")
        let calls = Mutex<[RootContract.Command]>([])
        let batch = CleanSystemRootClient(run: { command, _ in
            let attempt = calls.withLock { calls in
                calls.append(command)
                return calls.filter { $0 == .cleanSystemTrash }.count
            }
            if command == .version { return Data((RootContract.version + "\n").utf8) }
            if attempt == 1 { throw CleanSystem.Failure.refused }
            return Data("ok\n".utf8)
        }, policy: policy)
        let skipped = try await batch.trash([entry, entry])
        precondition(skipped == 1)
        precondition(calls.withLock { $0 } == [.version, .cleanSystemTrash, .cleanSystemTrash])
        print("PASS: batch continues after refusal, counts skips and checks version once")
        do {
            _ = try CleanSystem.inspect(folder.path + "/foo\0.gz")
            fatalError()
        } catch CleanSystem.Failure.refused {}
        let nul = CleanSystemEntry(path: folder.path + "/foo\0.gz", size: 1,
            modified: entry.modified, identity: entry.identity,
            isRegularFile: true, hasSymlinkComponent: false)
        precondition(policy.reason(for: nul) == nil)
        print("PASS: NUL path refused before syscalls and by app policy")
        let tree = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent(UUID().uuidString)
        try FileManager().createDirectory(at: tree, withIntermediateDirectories: false,
                                         attributes: [.posixPermissions: 0o700])
        defer { try? FileManager().removeItem(at: tree) }
        let source = tree.appendingPathComponent("source")
        let trash = tree.appendingPathComponent("Trash")
        for directory in [source, trash] {
            try FileManager().createDirectory(at: directory, withIntermediateDirectories: false,
                                             attributes: [.posixPermissions: 0o700])
        }
        let candidate = source.appendingPathComponent("cache")
        let sentinel = trash.appendingPathComponent("cache")
        try Data("sentinel".utf8).write(to: sentinel)
        try Data("allowed".utf8).write(to: candidate)
        let trashPolicy = CleanSystemPolicy(roots: [.init(path: source.path, rule: .caches)],
            now: .now.addingTimeInterval(100), cacheAge: 1, logAge: 1)
        let reviewed = try CleanSystem.inspect(candidate.path)
        try CleanSystem.trash(reviewed, policy: trashPolicy, destination: trash.path,
                              owner: getuid(), sourceOwner: getuid())
        let sentinelData = try Data(contentsOf: sentinel)
        precondition(sentinelData == Data("sentinel".utf8))
        precondition(!FileManager().fileExists(atPath: candidate.path))
        let trashed = try FileManager().contentsOfDirectory(atPath: trash.path)
        precondition(trashed.count == 2)
        let movedName = trashed.first { $0 != "cache" }!
        let movedData = try Data(contentsOf: trash.appendingPathComponent(movedName))
        precondition(movedData == Data("allowed".utf8))
        try Data("new".utf8).write(to: candidate)
        let changed = try CleanSystem.inspect(candidate.path)
        try Data("changed".utf8).write(to: candidate)
        do {
            try CleanSystem.trash(changed, policy: trashPolicy, destination: trash.path,
                                  owner: getuid(), sourceOwner: getuid())
            fatalError()
        } catch CleanSystem.Failure.refused {}
        var writable = try CleanSystem.inspect(candidate.path)
        for path in [source.path + "/../source/cache", tree.appendingPathComponent("outside").path] {
            if !path.contains("..") { try Data("outside".utf8).write(to: URL(fileURLWithPath: path)) }
            do {
                let item = try CleanSystem.inspect(path)
                try CleanSystem.trash(item, policy: trashPolicy, destination: trash.path,
                                      owner: getuid(), sourceOwner: getuid())
                fatalError()
            } catch CleanSystem.Failure.refused {}
        }
        let hardLink = source.appendingPathComponent("linked")
        try FileManager().linkItem(at: candidate, to: hardLink)
        do {
            let linked = try CleanSystem.inspect(candidate.path)
            try CleanSystem.trash(linked, policy: trashPolicy, destination: trash.path,
                                  owner: getuid(), sourceOwner: getuid())
            fatalError()
        } catch CleanSystem.Failure.refused {}
        try FileManager().removeItem(at: hardLink)
        writable = try CleanSystem.inspect(candidate.path)
        print("PASS: real trash refuses dot-dot, outside fixture and hard links")
        try FileManager().setAttributes([.posixPermissions: 0o770], ofItemAtPath: source.path)
        do {
            try CleanSystem.trash(writable, policy: trashPolicy, destination: trash.path,
                                  owner: getuid(), sourceOwner: getuid())
            fatalError()
        } catch CleanSystem.Failure.refused {}
        try FileManager().setAttributes([.posixPermissions: 0o700], ofItemAtPath: source.path)
        let renamed = tree.appendingPathComponent("renamed")
        try FileManager().moveItem(at: source, to: renamed)
        try FileManager().createSymbolicLink(at: source, withDestinationURL: renamed)
        do {
            try CleanSystem.trash(writable, policy: trashPolicy, destination: trash.path,
                                  owner: getuid(), sourceOwner: getuid())
            fatalError()
        } catch CleanSystem.Failure.refused {}
        print("PASS: real trash preserves collision; changed file, writable parent and symlink parent refused")
    }
}
