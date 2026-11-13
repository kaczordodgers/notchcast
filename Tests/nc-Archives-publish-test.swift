// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/JobOutput.swift
// notchcast-kit: platform
import Darwin
import Foundation

@main
struct ArchivesPublishTest {
    @MainActor static func main() async throws {
        let scratch = ProcessInfo.processInfo.environment["ARCHIVES_TEST_ROOT"]
            .map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let root = scratch.appending(path: "archives-publish-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? ArchiveFiles.removeStaging(root) }
        let fallbackStage = root.appending(path: "fallback-stage")
        try FileManager.default.createDirectory(at: fallbackStage, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        try Data("safe".utf8).write(to: fallbackStage.appending(path: "payload"))
        let fallbackOutput = try ArchiveFiles.publish(fallbackStage, staging: fallbackStage,
            archive: root.appending(path: "fallback.zip"), exclusiveRename: { _, _ in errno = ENOTSUP; return -1 })
        expect(try Data(contentsOf: fallbackOutput.appending(path: "payload")) == Data("safe".utf8), "ENOTSUP publishes content")
        expect(!fallbackOutput.path.contains("/.notchcast-"), "fallback is visible")
        print("PASS: ENOTSUP exclusive publication preserves visible content")
        let lockedStage = root.appending(path: "locked-stage")
        let lockedRoot = lockedStage.appending(path: "ReadOnly")
        try FileManager.default.createDirectory(at: lockedRoot, withIntermediateDirectories: true)
        try Data("locked".utf8).write(to: lockedRoot.appending(path: "payload"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: lockedRoot.path)
        let lockedOutput = try ArchiveFiles.publish(lockedRoot, staging: lockedStage,
                                                    archive: root.appending(path: "locked.zip"))
        expect(try Data(contentsOf: lockedOutput.appending(path: "payload")) == Data("locked".utf8),
               "read-only folder publishes")
        expect(try ArchiveFiles.attributes(lockedOutput).st_mode & 0o777 == 0o500, "read-only mode kept")
        let failedRoot = lockedStage.appending(path: "Failed")
        try FileManager.default.createDirectory(at: failedRoot, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o500])
        do {
            _ = try ArchiveFiles.publish(failedRoot, staging: lockedStage, archive: root.appending(path: "failed.zip"),
                                         exclusiveRename: { _, _ in errno = EIO; return -1 })
            expect(false, "failed rename throws")
        } catch ArchiveFailure.filesystem {}
        expect(try ArchiveFiles.attributes(failedRoot).st_mode & 0o777 == 0o500, "failed publish restores mode")
        print("PASS: read-only top folder publishes across parents and keeps its mode on failure")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
}
