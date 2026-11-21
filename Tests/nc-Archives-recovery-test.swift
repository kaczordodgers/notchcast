// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift

// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/*.swift

// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift

// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift

// notchcast-sources: Tinycast/Platform/NotificationToken.swift Tinycast/Platform/ProcessExit.swift

// notchcast-sources: Tinycast/Platform/ExecutableLocator.swift

// notchcast-sources: Tinycast/Features/Notchcast/Archives/ArchivesAddon.swift

// notchcast-sources: Tinycast/Features/Notchcast/Archives/Model/*.swift

// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesModule.swift

// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesEnvironment.swift

// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveExtractor.swift

// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveCompressor.swift

// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveProcess.swift

// notchcast-sources: Tests/NotchcastDictationFixture.swift

// notchcast-sources: Tests/nc-Archives-password-fixture.swift

import Foundation

@MainActor
func stoppedEncryptedNames(moved: Bool) async throws {
    var rig = try Rig(answers: [right], passwords: ["Vault.7z": right], hiddenNames: ["Vault.7z"])
    let folder = rig.folder
    rig.tools.state.withLock { $0.hold = ["Vault.7z"] }
    rig.module!.open([rig.archive("Vault.7z")])
    while !rig.tools.state.withLock({ $0.heldStarted }) { await Task.yield() }
    let staging = rig.module!.current!.job.staging
    rig.module!.cancel(rig.module!.current!.job.id)
    await rig.module!.drain()
    check(rig.steps == ["list", "list", "extract", "restore"] && rig.calls[3].environment.isEmpty, "\(rig.steps)")
    let stopped = rig.journal()
    check(stopped.count == 1 && stopped[0].stopped?.stoppedAt == Rig.testDate, "the stop records its time")
    check(rig.staging == [staging.lastPathComponent] && rig.exists("Vault.7z.hatchzip"), "staging kept: \(rig.visible)")
    check(rig.presenter.texts.last == "Stopped extracting Vault.7z", "\(rig.presenter.texts)")
    rig.module!.cancelAll()
    check(rig.journal().count == 1, "Cancel All Extractions keeps it")
    rig.controller.preferences.set("archives", on: false)
    while rig.module != nil { await Task.yield() }
    check(rig.staging.count == 1 && rig.journal().count == 1, "switching off keeps it too")
    rig.finish(keepingFolder: true)

    let files = FileManager.default
    let original = folder.appending(path: "Vault.7z")
    let reopened: URL
    if moved {
        let subfolder = folder.appending(path: "Moved", directoryHint: .isDirectory)
        try files.createDirectory(at: subfolder, withIntermediateDirectories: true)
        reopened = subfolder.appending(path: "Renamed.7z")
        try files.moveItem(at: original, to: reopened)
        try files.moveItem(atPath: original.path + ".hatchzip", toPath: reopened.path + ".hatchzip")
    } else {
        reopened = original
        try files.setAttributes([.modificationDate: Rig.testDate], ofItemAtPath: original.path)
        let modified = try files.attributesOfItem(atPath: original.path)[.modificationDate] as? Date
        check(modified == Rig.testDate, "the modification date changed")
    }
    let name = reopened.lastPathComponent
    rig = try Rig(folder: folder, answers: [nil], passwords: [name: right], hiddenNames: [name])
    await rig.module!.drain()
    check(rig.module!.current == nil && rig.calls.isEmpty && rig.record.asks.isEmpty, "a relaunch asks nothing")
    check(rig.presenter.posts.isEmpty, "and shows nothing running")
    let sideFile = URL(filePath: reopened.path + ".hatchzip")
    let sideContents = try Data(contentsOf: sideFile)
    let originalItems = rig.visible
    rig.module!.open([reopened])
    await rig.module!.drain()
    if moved {
        check(rig.steps == ["list"] && rig.record.asks.isEmpty, "HatchZip refuses the moved archive before asking")
        check(rig.presenter.failures == [
            "Undo moves or renames, side files too."
        ], "\(rig.presenter.failures)")
        check(rig.journal() == stopped && rig.visible == originalItems, "only the original stop and staging remain")
        check(try Data(contentsOf: sideFile) == sideContents, "the moved journal is untouched")
        check(!files.fileExists(atPath: reopened.deletingPathExtension().path), "no output beside the moved archive")
        check(try Data(contentsOf: staging.appending(path: "a.txt")) == Data("half".utf8), "partial output stays private")
        rig.finish(keepingFolder: true)
        let afterExpiry = try Rig(folder: folder, now: Rig.testDate.addingTimeInterval(7 * 24 * 60 * 60 + 1))
        defer { afterExpiry.finish() }
        await afterExpiry.module!.drain()
        check(afterExpiry.journal().isEmpty && afterExpiry.staging.isEmpty, "the missing original path expires")
        return
    }
    check(rig.record.asks.map(\.title) == ["Password for \(name)"], "opening it again asks for the current name")
    check(rig.journal() == stopped && rig.staging.count == 1, "Cancel keeps the same entry and staging")
    rig.record.answers = [right]
    rig.module!.open([reopened])
    await rig.module!.drain()
    let extractions = rig.calls.filter { $0.arguments[0] == "extract" }
    check(extractions.count == 1, "only one extraction: \(rig.steps)")
    check(extractions.last!.arguments.contains(staging.path), "resumed into the kept staging")
    let output = reopened.deletingPathExtension().appending(path: "b/c.txt")
    check(files.fileExists(atPath: output.path) && rig.staging.isEmpty, "placed beside the archive's current path")
    check(!files.fileExists(atPath: reopened.path + ".hatchzip"), "HatchZip cleared its state")
    check(rig.record.asks.count == 2 && rig.journal().isEmpty, "resume reuses this job's answer and clears the entry")
    rig.finish()
}

@MainActor
func stopWithoutSideFile(_ archive: URL) throws -> ArchiveJob {
    let files = FileManager.default
    var job = ArchiveJob(id: UUID(), archive: archive, inPlace: false)
    job.stopped = ArchiveFingerprint(size: ArchiveExtractor.size(archive)!, stoppedAt: Rig.testDate)
    try files.createDirectory(at: job.staging, withIntermediateDirectories: true)
    for name in ["a.txt", "partial.txt"] {
        try Data("half".utf8).write(to: job.staging.appending(path: name))
    }
    return job
}

@MainActor
func reopenWithoutSideFile(replaced: Bool) async throws {
    let files = FileManager.default
    let folder = files.temporaryDirectory.appending(path: "nc-archives-no-side-file-\(UUID())")
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: folder) }
    let archive = folder.appending(path: "Vault.7z")
    try Data("original".utf8).write(to: archive)
    let stopped = try stopWithoutSideFile(archive)
    if replaced {
        try Data("replaced".utf8).write(to: archive, options: .atomic)
        check(ArchiveExtractor.size(archive) == stopped.stopped?.size, "the replacement is the same size")
    }
    let rig = try Rig(folder: folder, answers: [right], journal: [stopped], passwords: ["Vault.7z": right])
    defer { rig.finish(keepingFolder: true) }
    await rig.extract("Vault.7z")
    let extracts = rig.calls.filter { $0.arguments[0] == "extract" }
    check(extracts.count == 1 && !extracts[0].arguments.contains(stopped.staging.path), "used fresh staging")
    check(rig.exists("Vault/a.txt") && rig.exists("Vault/b/c.txt"), "placed the fresh output")
    check(!rig.exists("Vault/partial.txt") && !rig.exists("partial.txt"), "never placed the old partial file")
    check(rig.journal().isEmpty && rig.staging.isEmpty, "removed the stopped record and staging")
}

@MainActor
func realHatchZipWithoutSideFile() async throws {
    guard let hatchzip = await ExecutableLocator.locate("hatchzip") else {
        print("SKIP real HatchZip reopen without side file: hatchzip is not installed")
        return
    }
    let files = FileManager.default
    let folder = files.temporaryDirectory.appending(path: "nc-archives-real-no-side-file-\(UUID())")
    let source = folder.appending(path: "src")
    try files.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: folder) }
    let archive = folder.appending(path: "Vault.zip")
    let inputs = ["a.txt", "b.txt"].map { source.appending(path: $0) }
    for file in inputs { try Data(file.lastPathComponent.utf8).write(to: file) }
    let zip = try await ArchiveProcess.run(URL(filePath: "/usr/bin/zip"),
                                          ["-q", "-j", "-P", right, archive.path] + inputs.map(\.path))
    check(zip.status == 0, "zip made the fixture: \(zip.errors)")
    let stopped = try stopWithoutSideFile(archive)
    let extractor = ArchiveExtractor(locate: { $0 == "hatchzip" ? hatchzip : nil },
                                     run: { try await ArchiveProcess.run($0, $1, environment: $2) })
    let rig = try Rig(folder: folder, answers: [right], journal: [stopped], extractor: extractor)
    defer { rig.finish(keepingFolder: true) }
    await rig.extract("Vault.zip")
    check(rig.presenter.failures.isEmpty, "\(rig.presenter.failures)")
    for file in inputs {
        let name = file.lastPathComponent
        let output = folder.appending(path: "Vault/\(name)")
        check(try Data(contentsOf: output) == Data(name.utf8), "extracted fresh contents for \(name)")
    }
    check(!rig.exists("Vault/partial.txt") && rig.journal().isEmpty && rig.staging.isEmpty, "discarded the old stop")
    print("real HatchZip reopen without side file: ok")
}

@MainActor
func startedElsewhere(foreignArchive: Bool) async throws {
    let files = FileManager.default
    let folder = files.temporaryDirectory.appending(path: "nc-archives-unknown-\(UUID())")
    let archive = folder.appending(path: "Vault.7z")
    let owner = foreignArchive ? folder.appending(path: "Other.7z") : archive
    var stopped = ArchiveJob(id: UUID(), archive: owner, inPlace: false)
    stopped.stopped = ArchiveFingerprint(size: foreignArchive ? 7 : 1, stoppedAt: Rig.testDate)
    let reported = foreignArchive ? stopped.staging : folder.appending(path: "Unknown output")
    let sentinel = Data("untouched".utf8)
    for folder in Set([stopped.staging, reported]) {
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try sentinel.write(to: folder.appending(path: "partial.txt"))
    }
    try Data("archive".utf8).write(to: archive)
    if foreignArchive { try Data("archive".utf8).write(to: owner) }
    let side = URL(filePath: archive.path + ".hatchzip")
    try FakeTools.writeJournal(archive: archive, output: reported)
    let sideContents = try Data(contentsOf: side)
    let rig = try Rig(folder: folder, answers: [right], journal: [stopped], passwords: ["Vault.7z": right])
    defer { rig.finish() }
    let originalItems = rig.visible
    await rig.extract("Vault.7z")
    check(rig.visible == originalItems, "nothing moved beside the opened archive")
    check(rig.calls.filter { $0.arguments[0] == "extract" }.count == 1, "the reported path was not retried")
    check(rig.presenter.failures == ["Finish this extraction with hatchzip first."],
          "\(rig.presenter.failures)")
    check(!rig.steps.contains("restore") && rig.journal() == [stopped], "the mismatched stopped entry stays")
    check(rig.staging == [stopped.staging.lastPathComponent], "only the fresh scratch folder is cleaned")
    for folder in Set([stopped.staging, reported]) {
        check(try Data(contentsOf: folder.appending(path: "partial.txt")) == sentinel, "partial files stay untouched")
    }
    check(try Data(contentsOf: side) == sideContents, "HatchZip's state stays untouched")
}

@MainActor
func pruneStopped() async throws {
    let files = FileManager.default
    let folder = files.temporaryDirectory.appending(path: "nc-archives-prune-\(UUID())")
    let weekAgo = Rig.testDate.addingTimeInterval(-7 * 24 * 60 * 60)
    let older = weekAgo.addingTimeInterval(-1)
    var entries: [ArchiveJob] = []
    for (name, stoppedAt) in [("Expired", older), ("Boundary", weekAgo), ("Recent", weekAgo.addingTimeInterval(1)),
                              ("Legacy", nil), ("Present", older)] {
        let archive = folder.appending(path: "\(name).7z")
        var job = ArchiveJob(id: UUID(), archive: archive, inPlace: false)
        job.stopped = ArchiveFingerprint(size: 7, stoppedAt: stoppedAt)
        try files.createDirectory(at: job.staging, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: job.staging.appending(path: "partial.txt"))
        if name == "Present" { try Data("archive".utf8).write(to: archive) }
        entries.append(job)
    }
    let rig = try Rig(folder: folder, journal: entries, now: Rig.testDate)
    defer { rig.finish() }
    await rig.module!.drain()
    check(rig.journal() == Array(entries.dropFirst()), "only the missing archive older than one week is pruned")
    check(!files.fileExists(atPath: entries[0].staging.path), "expired staging is removed")
    check(rig.staging.count == 4 && rig.calls.isEmpty && rig.presenter.posts.isEmpty, "other stops remain idle")
}

@main
enum ArchivesRecoveryTest {
    @MainActor
    static func main() async throws {
        try await stoppedEncryptedNames(moved: false)
        try await stoppedEncryptedNames(moved: true)
        try await reopenWithoutSideFile(replaced: false)
        try await reopenWithoutSideFile(replaced: true)
        try await realHatchZipWithoutSideFile()
        try await startedElsewhere(foreignArchive: false)
        try await startedElsewhere(foreignArchive: true)
        try await pruneStopped()
        print("nc-Archives-recovery-test: ok")
    }
}
