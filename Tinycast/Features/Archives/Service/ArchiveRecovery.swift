import Foundation
import Darwin

nonisolated struct ArchiveRecovery: Codable {
    enum State: String, Codable { case running, finishedExtract, publishing }
    let archive: URL
    let staging: URL
    let inPlace: Bool
    var state: State
    var owner: Int32? = getpid()

    static let key = "archiveRecoveryParents"
    var sidecar: URL { URL(fileURLWithPath: staging.path + ".json") }

    private var resolved: Self {
        Self(archive: ArchiveFiles.resolvedParent(archive), staging: ArchiveFiles.resolvedParent(staging),
             inPlace: inPlace, state: state, owner: owner)
    }

    func save() throws {
        var parents = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        let parent = staging.deletingLastPathComponent().path
        if !parents.contains(parent) { parents.append(parent) }
        UserDefaults.standard.set(parents, forKey: Self.key)
        try JSONEncoder().encode(self).write(to: sidecar, options: .atomic)
    }

    func remove() throws {
        if ArchiveFiles.exists(sidecar) { try FileManager.default.removeItem(at: sidecar) }
    }

    static func recoverKnown() throws -> [ArchiveJob] {
        var jobs: [ArchiveJob] = []
        for path in UserDefaults.standard.stringArray(forKey: key) ?? [] {
            let parent = URL(fileURLWithPath: path)
            guard ArchiveFiles.exists(parent) else { continue }
            try recover(in: parent)
            for file in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            where file.lastPathComponent.hasPrefix(ArchiveFiles.stagingPrefix) && file.pathExtension == "json" {
                let record = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file)).resolved
                let owner = record.owner ?? 0
                guard record.inPlace, record.state == .running,
                      owner == 0 || kill(owner, 0) != 0,
                      let journal = try ArchiveJournal.read(record.archive) else { continue }
                var job = ArchiveJob(id: UUID(), archive: record.archive, mode: .inPlace)
                job.state = .cancelled
                job.effectiveMode = .inPlace
                job.recovery = journal.recovery
                jobs.append(job)
            }
        }
        return jobs
    }

    @discardableResult static func recover(in parent: URL, archive: URL? = nil) throws -> URL? {
        let parent = ArchiveFiles.resolvedDirectory(parent)
        let archive = archive.map(ArchiveFiles.resolvedParent)
        let children = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
        for sidecar in children where sidecar.lastPathComponent.hasPrefix(ArchiveFiles.stagingPrefix)
            && sidecar.pathExtension == "json" {
            let record = try JSONDecoder().decode(Self.self, from: Data(contentsOf: sidecar)).resolved
            if let archive, !ArchiveFiles.samePath(record.archive, archive) { continue }
            guard ArchiveFiles.samePath(record.sidecar, sidecar) else { throw ArchiveFailure.existingProgress }
            if let owner = record.owner, owner != 0, kill(owner, 0) == 0 { continue }
            if !ArchiveFiles.exists(record.staging) { try record.remove(); continue }
            try ArchiveJournal.validateStaging(record.staging, archive: record.archive)
            let consumed = record.inPlace && !ArchiveFiles.exists(record.archive)
                && !ArchiveFiles.exists(URL(fileURLWithPath: record.archive.path + ".hatchzip"))
            if record.state != .running || consumed {
                let output = try publish(record)
                if archive != nil { return output }
            } else if !record.inPlace, ArchiveFiles.exists(record.archive) {
                try ArchiveExtractionRunner.cleanupKeepProgress(record.archive, staging: record.staging)
                try ArchiveFiles.removeStaging(record.staging)
                try record.remove()
            }
        }
        guard archive == nil else { return nil }
        for staging in children
        where UUID(uuidString: String(staging.lastPathComponent.dropFirst(ArchiveFiles.stagingPrefix.count))) != nil
            && staging.lastPathComponent.hasPrefix(ArchiveFiles.stagingPrefix) {
            guard ArchiveFiles.exists(staging) else { continue }
            guard !ArchiveFiles.exists(URL(fileURLWithPath: staging.path + ".json")) else { continue }
            let journals = children.filter { $0.pathExtension == "hatchzip" }
            let protected = journals.contains { journal in
                guard let data = try? Data(contentsOf: journal),
                      let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let output = saved["output"] as? String else { return true }
                return ArchiveFiles.samePath(URL(fileURLWithPath: output), staging)
            }
            guard !protected else { continue }
            let source = parent.appending(path: "Recovered archive.zip")
            try ArchiveJournal.validateStaging(staging, archive: source)
            if try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty {
                try ArchiveFiles.removeStaging(staging)
            } else {
                _ = try publish(Self(archive: source, staging: staging, inPlace: false, state: .finishedExtract))
            }
        }
        return nil
    }

    static func publish(_ record: Self) throws -> URL {
        var publishing = record
        publishing.state = .publishing
        try publishing.save()
        let root = try ArchiveFiles.prepare(record.staging, quarantine: ArchiveFiles.quarantine(record.staging))
        let output = try ArchiveFiles.publish(root, staging: record.staging, archive: record.archive, recovered: true)
        try ArchiveFiles.removeStaging(record.staging)
        try record.remove()
        return output
    }
}
