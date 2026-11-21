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

// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandSongArt.swift Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/UI/IslandTone+Ink.swift

import AppKit
import Synchronization

/// Acceptance 1: one question, then list, extract and the done notice, for a ZIP and a 7z.
@MainActor
func rightFirstTime() async throws {
    for (name, stem) in [("Photos.zip", "Photos"), ("Set.7z", "Set")] {
        let rig = try Rig(answers: [right], passwords: [name: right])
        defer { rig.finish() }
        await rig.extract(name)
        check(rig.record.asks == [Record.Ask(title: "Password for \(name)", message: nil, field: "Password",
                                            confirm: "Extract")], "\(rig.record.asks)")
        check(rig.steps == ["list", "list", "extract"], "\(rig.steps)")
        check(rig.calls[0].environment.isEmpty, "the first listing runs without a password")
        check(rig.calls[1...].allSatisfy { $0.environment == [variable: right] }, "then HatchZip gets it")
        check(rig.calls[2].arguments.contains("--keep-archive"), "kept, as by default")
        check(rig.exists("\(stem)/b/c.txt") && rig.exists(name), "\(rig.visible)")
        check(rig.presenter.texts == ["Extracting \(name)", "Extracted \(stem)"], "\(rig.presenter.texts)")
        check(rig.journal().isEmpty, "\(rig.journal())")
    }
}

@MainActor
func wrongThenRight() async throws {
    let rig = try Rig(answers: [wrong, right], passwords: ["Photos.zip": right])
    defer { rig.finish() }
    await rig.extract("Photos.zip")
    check(rig.record.asks.map(\.message) == [nil, "That password did not work."], "\(rig.record.asks)")
    check(rig.record.besideAtAsk == [["Photos.zip"], ["Photos.zip"]], "nothing beside it before: \(rig.record.besideAtAsk)")
    check(rig.exists("Photos/a.txt"), "\(rig.visible)")
}

@MainActor
func threeWrong() async throws {
    let rig = try Rig(answers: [wrong, wrong, wrong, right], passwords: ["Photos.zip": right])
    defer { rig.finish() }
    let before = rig.bytes("Photos.zip")
    await rig.extract("Photos.zip", "Next.zip")
    check(rig.record.asks.count == 3, "exactly three questions: \(rig.record.asks.count)")
    check(rig.presenter.failures == ["The password was not accepted."], "\(rig.presenter.failures)")
    check(rig.bytes("Photos.zip") == before, "the archive is unchanged")
    check(rig.visible == ["Next", "Next.zip", "Photos.zip"], "no staging, and the next one ran: \(rig.visible)")
    check(rig.journal().isEmpty, "\(rig.journal())")
}

@MainActor
func cancelAtQuestion() async throws {
    let rig = try Rig(answers: [nil], passwords: ["Photos.zip": right])
    defer { rig.finish() }
    let before = rig.bytes("Photos.zip")
    await rig.extract("Photos.zip", "Next.zip")
    check(rig.calls.filter { $0.arguments[1].hasSuffix("Photos.zip") }.count == 1, "no tool after Cancel")
    check(rig.presenter.texts.contains("Stopped extracting Photos.zip"), "\(rig.presenter.texts)")
    check(rig.presenter.failures.isEmpty, "\(rig.presenter.failures)")
    check(rig.bytes("Photos.zip") == before && rig.visible == ["Next", "Next.zip", "Photos.zip"], "\(rig.visible)")
    check(rig.journal().isEmpty, "\(rig.journal())")
}

@MainActor
func notAskedWhenNotNeeded() async throws {
    let rig = try Rig()
    defer { rig.finish() }
    await rig.extract("Plain.zip", "src.tar.zst")
    check(rig.record.asks.isEmpty, "no question")
    check(rig.calls.allSatisfy { $0.environment.isEmpty }, "no extra environment")
    check(rig.exists("Plain/a.txt") && rig.exists("src/a.txt"), "\(rig.visible)")
}

@MainActor
func noSpaceWithPassword() async throws {
    var rig = try Rig(answers: [right], passwords: ["Photos.zip": right])
    rig.tools.state.withLock { $0.extractStatuses = [3] }
    await rig.extract("Photos.zip")
    check(rig.steps == ["list", "list", "extract", "check", "extract"], "\(rig.steps)")
    check(rig.calls[3].environment == [variable: right], "check carries the password")
    check(rig.record.confirms.count == 1, "the in-place question is asked")
    check(rig.calls[4].arguments.contains("-y") && rig.calls[4].environment == [variable: right], "and the run in place")
    rig.finish()

    rig = try Rig(answers: [right], passwords: ["Set.7z": right])
    rig.tools.state.withLock { $0.extractStatuses = [3] }
    await rig.extract("Set.7z")
    check(rig.steps == ["list", "list", "extract", "restore"], "no check for a protected 7z: \(rig.steps)")
    check(rig.record.confirms.isEmpty, "no in-place question")
    check(rig.presenter.failures == ["no room"], "\(rig.presenter.failures)")
    rig.finish()

    rig = try Rig(answers: [right], passwords: ["Set.7z": right])
    rig.defaults.set(true, forKey: "archivesInPlace")
    rig.tools.state.withLock { $0.hold = ["Set.7z"] }
    rig.module!.open([rig.archive("Set.7z")])
    while !rig.tools.state.withLock({ $0.heldStarted }) { await Task.yield() }
    check(rig.calls.last!.arguments.contains("--keep-archive"), "a protected 7z is kept despite the option")
    check(rig.tools.state.withLock { $0.journalInPlaceAtExtract } == [false], "the journal says kept first")
    rig.module!.cancel(rig.module!.current!.job.id)
    await rig.module!.drain()
    check(rig.visible == ["Set.7z"], "a stop leaves no staging and places nothing: \(rig.visible)")
    rig.finish()
}

@MainActor
func extractRefusesAfterProvenPassword() async throws {
    let rig = try Rig(answers: [right, right], passwords: ["Photos.rar": right])
    defer { rig.finish() }
    rig.tools.state.withLock { $0.extractStatuses = [5] }
    await rig.extract("Photos.rar")
    check(rig.record.asks.count == 1, "no second round of questions")
    check(rig.presenter.failures == ["The password was not accepted."], "\(rig.presenter.failures)")
}

@MainActor
func passwordFirstNeededAtExtract() async throws {
    for answers in [[wrong, wrong, right], [wrong, wrong, wrong]] {
        let name = "First at extract.rar"
        let rig = try Rig(answers: answers, passwords: [name: right])
        defer { rig.finish() }
        rig.defaults.set(true, forKey: "archivesInPlace")
        rig.tools.state.withLock { $0.extractOnlyPasswords = [name] }
        await rig.extract(name)
        check(rig.record.asks.map(\.message) == [nil, "That password did not work.", "That password did not work."],
              "extract gets the same three attempts as listing")
        check(rig.record.besideAtAsk == Array(repeating: [name], count: 3), "no scratch folder while asking")
        check(rig.calls.dropFirst(2).allSatisfy { $0.arguments.contains("--keep-archive") },
              "after asking, RAR retries always keep the archive")
        if answers.last == right {
            check(rig.exists("First at extract/a.txt") && rig.presenter.failures.isEmpty, "third password extracts")
        } else {
            check(rig.visible == [name] && rig.presenter.failures == ["The password was not accepted."],
                  "the third refusal stops the loop")
        }
    }
}

@MainActor
func noHook() async throws {
    let rig = try Rig(hook: false, passwords: ["Photos.zip": right])
    defer { rig.finish() }
    let before = rig.bytes("Photos.zip")
    await rig.extract("Photos.zip")
    check(rig.presenter.failures == ["The password was not accepted."], "\(rig.presenter.failures)")
    check(rig.steps == ["list"] && rig.bytes("Photos.zip") == before, "\(rig.steps)")
}

@MainActor
func switchOffWhileAsking() async throws {
    let rig = try Rig(answers: [right], passwords: ["Photos.zip": right])
    defer { rig.finish() }
    rig.record.holdAsk = true
    rig.module!.open([rig.archive("Photos.zip")])
    let task = rig.module!.current!.task
    while rig.record.heldAsk == nil { await Task.yield() }
    rig.controller.preferences.set("archives", on: false)
    while rig.module != nil { await Task.yield() }
    rig.record.heldAsk?.resume()
    await task.value
    check(rig.steps == ["list"], "no tool runs once the answer arrives: \(rig.steps)")
    check(rig.journal().map(\.name) == ["Photos.zip"], "the job stays to resume")
}

@MainActor
func resumeAfterRelaunch() async throws {
    for answer in [right, nil] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nc-archives-pw-\(UUID())")
        let job = ArchiveJob(id: UUID(), archive: folder.appending(path: "Photos.zip"), inPlace: true)
        try FileManager.default.createDirectory(at: job.staging, withIntermediateDirectories: true)
        try Data("archive".utf8).write(to: job.archive)
        try Data("x".utf8).write(to: job.staging.appending(path: "a.txt"))
        try FakeTools.writeJournal(archive: job.archive, output: job.staging)
        let rig = try Rig(folder: folder, answers: [answer], journal: [job], passwords: ["Photos.zip": right])
        defer { rig.finish() }
        await rig.module!.drain()
        check(rig.record.asks.count == 1, "a resumed job asks again")
        if answer == nil {
            check(rig.steps == ["list", "restore"], "\(rig.steps)")
            check(rig.exists("a.txt") && rig.presenter.texts.contains("Stopped extracting Photos.zip"), "\(rig.visible)")
        } else {
            check(rig.steps == ["list", "list", "extract"] && rig.calls[2].arguments.contains("-y"), "\(rig.steps)")
            check(rig.exists("Photos/b/c.txt"), "\(rig.visible)")
        }
        check(rig.journal().isEmpty, "\(rig.journal())")
    }
}

@MainActor
func eachArchiveAsks() async throws {
    let rig = try Rig(answers: [right, right], passwords: ["One.zip": right, "Two.7z": right])
    defer { rig.finish() }
    await rig.extract("One.zip", "Two.7z")
    check(rig.record.asks.map(\.title) == ["Password for One.zip", "Password for Two.7z"], "\(rig.record.asks)")
    let second = rig.calls.first { $0.arguments[1].hasSuffix("Two.7z") }!
    check(second.environment.isEmpty, "the first password is not reused")
}

func realHatchZip() async throws {
    guard let hatchzip = await ExecutableLocator.locate("hatchzip") else {
        print("SKIP real HatchZip passwords: hatchzip is not installed (brew install xevrion/tap/hatchzip)")
        return
    }
    print("SKIP real HatchZip stop on encrypted names: needs a multi-GB fixture; the PR's probe 3(c) is the proof")
    let secret = "nc-secret-7Qx"
    let root = FileManager.default.temporaryDirectory.appending(path: "nc-archives-pw-real-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
    for (file, text) in [("a", "one"), ("b", "two")] { try Data(text.utf8).write(to: root.appending(path: "src/\(file).txt")) }
    let fixtures: [(String, Data?)] = [
        ("crypto.zip", nil),
        ("aes.zip", Data(base64Encoded: """
            UEsDBDMAAQBjAI1xdV0AAAAAHwAAAAMAAAAFAAsAYS50eHQBmQcAAgBBRQMAAKYZs21vScJxpfuOAhgJzoQGzQtI6x6nnX34c12b1D5QSwMEMwAB\
            AGMAjXF1XQAAAAAfAAAAAwAAAAUACwBiLnR4dAGZBwACAEFFAwAAHy5F529krZLKhBOZjDWaPFLdI4qXDyfQgMEAuejTY1BLAQI/AzMAAQBjAI1x\
            dV0AAAAAHwAAAAMAAAAFAC8AAAAAAAAAIICkgQAAAABhLnR4dAoAIAAAAAAAAQAYAMdl6vK5ed0BAAAAAAAAAAAAAAAAAAAAAAGZBwACAEFFAwAA\
            UEsBAj8DMwABAGMAjXF1XQAAAAAfAAAAAwAAAAUALwAAAAAAAAAggKSBTQAAAGIudHh0CgAgAAAAAAABABgAlWnq8rl53QEAAAAAAAAAAAAAAAAA\
            AAAAAZkHAAIAQUUDAABQSwUGAAAAAAIAAgDEAAAAmgAAAAAA
            """)),
        ("aes.7z", Data(base64Encoded: """
            N3q8ryccAASI2s4uhwAAAAAAAAAhAAAAAAAAAIPqTDwvibsFtEUPpi08+8DRJkp4AACBMweuD87ysgwHsMPa919FiphISviu0zhwQOmxenRQLD0B\
            HLYfDoyz/T3c4gcCy47DCBGKL+oQ5F6wSgEEb7bQhBqj6PcEZZlhBGaMBHMJ97+xkAodFFc3x+xNQ6+jZHt8GVYWqdELNqtxRKmsgSgEBBRNAAAX\
            BhABCXcABwsBAAEjAwEBBV0AEAAADICOCgFd4t40AAA=
            """)),
    ]
    let seen = Mutex<[[String]]>([])
    let extractor = ArchiveExtractor(locate: { $0 == "hatchzip" ? hatchzip : nil }, run: { tool, arguments, extra in
        seen.withLock { $0.append(arguments) }
        return try await ArchiveProcess.run(tool, arguments, environment: extra)
    })
    for (name, data) in fixtures {
        for attempt in [wrong, secret] {
            let folder = root.appending(path: "\(attempt == secret ? "right" : "wrong")-\(name)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let archive = folder.appending(path: name)
            if let data {
                try data.write(to: archive)
            } else {
                let zip = try await ArchiveProcess.run(URL(filePath: "/usr/bin/zip"), [
                    "-q", "-j", "-P", secret, archive.path, root.appending(path: "src/a.txt").path,
                    root.appending(path: "src/b.txt").path])
                check(zip.status == 0, "zip made the fixture: \(zip.errors)")
            }
            let before = try Data(contentsOf: archive)
            let job = ArchiveJob(id: UUID(), archive: archive, inPlace: false)
            seen.withLock { $0.removeAll() }
            do {
                let placed = try await extractor.extract(
                    job, askPassword: { _ in attempt }, askInPlace: { _ in false }, onInPlace: { _ in })
                check(attempt == secret, "\(name): a wrong password extracted")
                let stem = URL(filePath: name).deletingPathExtension().lastPathComponent
                check(placed?.lastPathComponent == stem, "\(name): \(String(describing: placed))")
                let text = try String(contentsOf: placed!.appending(path: "b.txt"), encoding: .utf8)
                check(text == "two", "\(name): the files come out")
            } catch ArchiveFailure.password {
                check(attempt == wrong, "\(name): the right password was refused")
                check(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [name],
                      "\(name): nothing beside it after wrong ones")
            }
            check(try Data(contentsOf: archive) == before, "\(name): the archive is byte-identical")
            check(!seen.withLock { $0 }.joined().contains { $0.contains(marker) }, "\(name): a password in arguments")
        }
    }
    print("real HatchZip passwords: ok")
}

@MainActor
func islandCopyFits() async throws {
    let stem = String(repeating: "Wide filename ", count: 15) + "backup"
    let name = stem + ".zip"
    let rig = try Rig(answers: [wrong, right, nil], passwords: [name: right])
    defer { rig.finish() }

    await rig.extract(name)
    await rig.extract(name)
    check(rig.record.asks.map(\.title) == Array(repeating: "Password for \(name)", count: 3),
          "the wrapping dialog gets the full title")
    check(rig.record.asks.map(\.message) == [nil, "That password did not work.", nil], "retry copy is intact")
    check(rig.presenter.texts == ["Extracting \(name)", "Extracted \(stem)", "Extracting \(name)",
                                  "Stopped extracting \(name)"], "each notice starts with its status")

    let font = NotchTheme.Typography.islandGlanceNSFont
    let markAndGap = font.pointSize + Theme.Spacing.xs + Theme.Spacing.sm
    func checkFits(_ text: String, in notice: IslandNotice) {
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        for frosted in [false, true] {
            let pill = IslandNoticeArt(notice, notch: false, frosted: frosted).layout
            check(width <= pill.leading + pill.trailing - markAndGap, "pill clips \(text)")
            let headline = IslandHeadlineArt(notice, notch: 1, frosted: frosted)
            check(width <= headline.textWidth, "notch headline clips \(text)")
        }
    }
    for (notice, prefix) in zip(rig.presenter.posts, ["Extracting W…", "Extracted W…", "Extracting W…",
                                                       "Stopped extracting W…"]) {
        checkFits(prefix, in: notice)
    }
    for failure in [ArchiveFailure.resumeJournalMismatch, .startedElsewhere(""), .password] {
        let notice = IslandNotice(id: "archives.failed", symbol: "exclamationmark.triangle",
                                  text: failure.message, isFailure: true)
        checkFits(notice.text, in: notice)
    }
}

@main
enum ArchivesPasswordTest {
    @MainActor
    static func main() async throws {
        try await rightFirstTime()
        try await wrongThenRight()
        try await threeWrong()
        try await cancelAtQuestion()
        try await notAskedWhenNotNeeded()
        try await noSpaceWithPassword()
        try await extractRefusesAfterProvenPassword()
        try await passwordFirstNeededAtExtract()
        try await noHook()
        try await switchOffWhileAsking()
        try await resumeAfterRelaunch()
        try await eachArchiveAsks()
        try await islandCopyFits()
        try await realHatchZip()
        print("nc-Archives-password-test: ok")
    }
}
