// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-sources: Tinycast/Features/Archives/ArchiveModule.swift
// notchcast-sources: Tinycast/Features/Archives/NotchcastArchiveModules.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-kit: platform
import Foundation

@MainActor enum NotchcastCore {}

@MainActor
final class FakeArchiveDefaults: ArchiveDefaultApplicationSetting {
    var calls: [Bool] = []
    var applications: [URL] = []
    var suspended: CheckedContinuation<Void, any Error>?
    var hold = false

    func setEnabled(_ enabled: Bool, application: URL) async throws {
        calls.append(enabled)
        applications.append(application)
        if hold {
            try await withCheckedThrowingContinuation { suspended = $0 }
        }
    }

    func finish(failing: Bool = false) {
        let continuation = suspended
        suspended = nil
        if failing {
            continuation?.resume(throwing: ArchiveFailure.toolFailed(1))
        } else {
            continuation?.resume()
        }
    }
}

@main @MainActor
struct ArchiveModulesTests {
    struct Locator: ArchiveToolLocating {
        let tool: URL?
        func locate() -> URL? { tool }
    }

    static func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    static func until(_ condition: () -> Bool) async throws {
        while !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    static func main() async throws {
        let suite = "archive-modules.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(preferences.isOn(.archives))
        for feature: NotchcastFeature in [.archivesInPlace, .archivesDefaultApp] {
            precondition(!preferences.isOn(feature) && !feature.defaultEnabled)
            precondition(feature.dependencies == [.archives])
        }
        for feature: NotchcastFeature in [.archives, .archivesInPlace, .archivesDefaultApp] {
            precondition(!feature.needsIsland && feature.requiredGrants.isEmpty)
            precondition(!feature.title.isEmpty && !feature.subtitle.isEmpty)
        }
        let service = FakeArchiveDefaults()
        let application = URL(fileURLWithPath: "/fixture/Notchcast.app")
        let module = ArchiveModule(preferences: preferences, locator: Locator(tool: nil),
                                   defaultApplications: service, application: application)
        let entries = NotchcastCore.archiveModuleEntries(module)
        precondition(entries.count == 1 && entries[0].requires == [.archives])
        let controller = NotchcastModuleController(entries, preferences: preferences)
        controller.run()
        precondition(module.isRunning && service.calls.isEmpty)
        module.start()
        preferences.set(.island, false)
        await settle()
        precondition(module.isRunning)
        precondition(!module.open(URL(string: "https://example.invalid/file.zip")!))
        precondition(!module.open(URL(fileURLWithPath: "/fixture/file.txt")))
        for name in ["file.zip", "file.7z", "file.rar", "file.part1.rar", "file.tar", "file.tgz", "file.tar.gz", "file.001"] {
            precondition(module.open(URL(fileURLWithPath: "/fixture/\(name)")))
        }
        precondition(module.queue.jobs.allSatisfy { $0.mode == .keepArchive })
        preferences.set(.archivesInPlace, true)
        precondition(module.open(URL(fileURLWithPath: "/fixture/in-place.zip")))
        precondition(module.queue.jobs.last?.mode == .inPlace)
        try await until { module.queue.jobs.allSatisfy { $0.state == .failed } }
        precondition(module.queue.jobs.allSatisfy { $0.failure == .toolMissing })
        let failed = module.queue.jobs[0].id
        module.retry(failed)
        precondition(module.queue.jobs[0].state == .preflighting)
        try await until { module.queue.jobs[0].state == .failed }
        precondition(module.open(URL(fileURLWithPath: "/fixture/file.gz")))
        try await until { module.queue.jobs.last?.state == .failed }
        guard case .filesystem = module.queue.jobs.last?.failure else {
            preconditionFailure("Plain gzip routes without hatchzip and reports its missing source")
        }
        preferences.set(.archives, false)
        let count = module.queue.jobs.count
        precondition(!module.open(URL(fileURLWithPath: "/fixture/disabled.zip")))
        module.retry(failed)
        precondition(module.queue.jobs[0].state == .failed && module.queue.jobs.count == count)
        await settle()
        precondition(!module.isRunning && service.calls.isEmpty)
        preferences.set(.archives, true)
        await settle()
        precondition(module.isRunning)
        preferences.set(.archivesDefaultApp, true)
        try await until { service.calls == [true] }
        precondition(service.applications == [application])
        await settle()
        let reopenedService = FakeArchiveDefaults()
        let reopened = ArchiveModule(preferences: NotchcastPreferences(suiteName: suite),
            locator: Locator(tool: nil), defaultApplications: reopenedService)
        reopened.start()
        await settle()
        precondition(reopenedService.calls.isEmpty, "launch preserves user's current handler")
        preferences.set(.archivesDefaultApp, false)
        try await until { service.calls == [true, false] }
        preferences.set(.archivesDefaultApp, true)
        try await until { service.calls.count == 3 }
        preferences.set(.archives, false)
        try await until { service.calls == [true, false, true, false] }
        preferences.set(.archivesDefaultApp, false)
        await settle()
        preferences.set(.archives, true)
        await settle()
        precondition(service.calls.count == 4)
        precondition(NotchcastPreferences(suiteName: suite).isOn(.archivesInPlace))
        await module.refreshTool()
        precondition(module.toolURL == nil)
        try await handlerRaces()
        try await cancellation()
        print("PASS: production registration, lifecycle, defaults, switch gating, routing, modes, retry, tool status")
        print("PASS: fake default-app enable/restore, parent dependency, rapid toggles, partial failures, quit")
    }

    static func handlerRaces() async throws {
        let suite = "archive-handler-races.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let service = FakeArchiveDefaults()
        service.hold = true
        let module = ArchiveModule(preferences: preferences, locator: Locator(tool: nil), defaultApplications: service)
        module.start()
        preferences.set(.archivesDefaultApp, true)
        try await until { service.suspended != nil }
        preferences.set(.archivesDefaultApp, false)
        await settle()
        precondition(service.calls == [true], "handler updates are serialized")
        service.finish(failing: true)
        try await until { service.calls == [true, false] && service.suspended != nil }
        service.finish()
        await settle()
        precondition(module.defaultApplicationFailure == nil)
        preferences.set(.archivesDefaultApp, true)
        try await until { service.calls.count == 3 && service.suspended != nil }
        service.finish(failing: true)
        await settle()
        precondition(module.defaultApplicationFailure != nil)
        preferences.set(.archivesDefaultApp, false)
        try await until { service.calls.count == 4 && service.suspended != nil }
        service.finish()
        await settle()
        preferences.set(.archivesDefaultApp, true)
        try await until { service.calls.count == 5 && service.suspended != nil }
        service.finish()
        await settle()
        preferences.set(.archivesDefaultApp, false)
        try await until { service.calls.count == 6 && service.suspended != nil }
        preferences.set(.archivesDefaultApp, true)
        await settle()
        service.finish(failing: true)
        try await until { service.calls.count == 7 && service.suspended != nil }
        precondition(service.calls.last == true, "failed partial restore reclaims when switched back on")
        service.finish()
        await settle()
        await module.prepareForTermination()
        precondition(service.calls.last == true, "quit preserves the opted-in default handler")
        module.stop()
        try await until { service.calls.count == 8 && service.suspended != nil }
        service.finish()
        await settle()
        module.start()
        try await until { service.calls.count == 9 && service.suspended != nil }
        service.finish()
        await settle()
        preferences.set(.archivesDefaultApp, false)
        service.hold = false
        await module.prepareForTermination()
        precondition(service.calls.count == 10 && service.calls.last == false,
                     "quit applies a switch changed before its observation callback")
    }

    static func cancellation() async throws {
        let suite = "archive-stop.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let scratch = ProcessInfo.processInfo.environment["ARCHIVES_TEST_ROOT"]
            .map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let root = scratch.appending(path: "archives-module-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? ArchiveFiles.removeStaging(root) }
        let tool = root.appending(path: "hatchzip")
        let archive = root.appending(path: "slow.zip")
        let marker = root.appending(path: "started")
        let script = #"""
        #!/usr/bin/python3
        import pathlib, signal, sys, time
        args = sys.argv[1:]
        archive = pathlib.Path(args[-1])
        if args[0] == 'list':
            print('       4 B  result.txt')
            print('1 entry, 4 B uncompressed, 100 B zip archive')
        elif args[0] == 'extract':
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            (archive.parent / 'started').touch()
            time.sleep(30)
        """#
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        try Data("fixture".utf8).write(to: archive)
        let preferences = NotchcastPreferences(suiteName: suite)
        let module = ArchiveModule(preferences: preferences, locator: Locator(tool: tool),
                                   defaultApplications: FakeArchiveDefaults())
        let controller = NotchcastModuleController(NotchcastCore.archiveModuleEntries(module), preferences: preferences)
        controller.run()
        await module.refreshTool()
        precondition(module.toolURL == tool)
        precondition(module.open(archive))
        try await until { FileManager.default.fileExists(atPath: marker.path) }
        precondition(module.open(root.appending(path: "pending.zip")))
        preferences.set(.archives, false)
        try await until { !module.isRunning }
        await module.queue.waitUntilIdle()
        precondition(module.queue.jobs.map(\.state) == [.cancelled, .cancelled])
        precondition(FileManager.default.fileExists(atPath: archive.path))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        precondition(remaining.allSatisfy { !$0.hasPrefix(".notchcast-extract-") })
        preferences.set(.archives, true)
        await settle()
        module.retry(module.queue.jobs[0].id)
        try await until { module.queue.jobs[0].state == .extracting }
        await module.prepareForTermination()
        precondition(module.queue.jobs[0].state == .cancelled)
    }
}
