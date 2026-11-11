// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/Soloist*.swift
// notchcast-sources: Tinycast/Features/Music/Service/Soloist*.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift Tinycast/Platform/AppPaths.swift
// notchcast-kit: platform
// notchcast-sources: Tinycast/Features/Music/Settings/SoloistFailure+Settings.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/Model/*.swift
// notchcast-sources: Tinycast/Features/SettingsBackup/ForkSettingsBackupRestore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
import CryptoKit
import Darwin
import Foundation
import Synchronization

private func check(_ condition: Bool, _ message: String = "check failed", line: UInt = #line) {
    precondition(condition, "\(message), line \(line)")
}

/// The app's list reads every feature's live values; the restore harness checks its key names.
extension NotchcastFeature.BackupKeys { static let all: [Self] = [] }

@main
struct SoloistRuntimeTest {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "soloist-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SoloistFiles(root: root)
        try keyChecks(root: root)
        try archiveChecks()
        try await installerChecks(root: root)
        try await leakChecks(files: files)
        logChecks()
        try await processChecks()
        print("PASS: key validation/import, archive refusal, hashed cache, expiry, retry per press, cancellation, scrubbed log")
    }

    @MainActor
    private static func keyChecks(root: URL) throws {
        var stored: String?
        var changes = 0
        let key = SoloistKey(read: { stored }, write: { stored = $0 })
        key.onChange = { changes += 1 }
        check(try !key.isSaved)
        try key.save("  fixture-token\n")
        check(stored == "fixture-token")
        for invalid in ["", " \n", "two words", "tab\tkey", "nul\0key", String(repeating: "x", count: 4_097)] {
            do { try key.save(invalid); preconditionFailure("accepted invalid key") } catch {
                check(stored == "fixture-token")
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "key")
        try Data(" imported-token\n".utf8).write(to: file)
        try key.importKey(from: file)
        check(stored == "imported-token")
        for data in [Data(), Data(repeating: 120, count: 4_097), Data([0xFF])] {
            try data.write(to: file)
            do { try key.importKey(from: file); preconditionFailure("accepted invalid file") } catch {
                check(stored == "imported-token")
            }
        }
        try key.remove()
        check(stored == nil && changes == 3)
        let refusal = SoloistKey(read: { throw SoloistFailure.keyUnavailable }, write: { _ in
            throw SoloistFailure.keyUnavailable
        })
        do { _ = try refusal.value(); preconditionFailure("lost keychain error") } catch {}
    }

    private static func archiveChecks() throws {
        let listing = """
        -rwxr-xr-x  0 build staff 12345 Oct 30 12:00 ./soloist
        -rw-r--r--  0 build staff 12000 Oct 30 12:00 THIRD_PARTY_LICENSES.txt
        -rw-r--r--  0 build staff 3000 Oct 30 12:00 CHANGELOG.md
        -rw-r--r--  0 build staff 100 Oct 30 12:00 README extra.txt
        """
        let entries = try SoloistArchiveRules.entries(listing)
        check(try SoloistArchiveRules.check(entries) == ["./soloist", "THIRD_PARTY_LICENSES.txt", "CHANGELOG.md"])
        let good = SoloistArchiveRules.Entry(kind: "-", size: 1, name: "soloist")
        let bad: [[SoloistArchiveRules.Entry]] = [
            [.init(kind: "l", size: 0, name: "soloist")],
            [.init(kind: "h", size: 0, name: "soloist")],
            [good, .init(kind: "p", size: 0, name: "pipe")],
            [good, .init(kind: "-", size: 0, name: "../escape")],
            [good, .init(kind: "-", size: 0, name: "/escape")],
            [good, .init(kind: "-", size: 0, name: "./soloist")],
            [.init(kind: "-", size: -1, name: "soloist")],
            [.init(kind: "-", size: Int.max, name: "soloist")],
            Array(repeating: good, count: 65), [],
        ]
        for archive in bad {
            do { _ = try SoloistArchiveRules.check(archive); preconditionFailure("accepted unsafe archive") } catch {}
        }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        check(SoloistBuild.isUsable(built: now.addingTimeInterval(-89 * 86_400), now: now))
        check(!SoloistBuild.isUsable(built: now.addingTimeInterval(-90 * 86_400), now: now))
        check(!SoloistBuild.isUsable(built: now.addingTimeInterval(2 * 86_400), now: now))
        check(SoloistBuild.parseVersion("soloist 1.3 build 2000000000 arm64")?.built == now)
        check(SoloistBuild.parseVersion("soloist 1.3 build inf") == nil)
    }

    @MainActor
    private static func installerChecks(root: URL) async throws {
        let clock = Mutex(Date(timeIntervalSince1970: 2_000_000_000))
        let fetched = Mutex(0)
        let files = SoloistFiles(root: root.appending(path: "builds-test"))
        let fixture = root.appending(path: "archive-input")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try Data("fixture build bytes".utf8).write(to: fixture.appending(path: "soloist"))
        try Data("ignored".utf8).write(to: fixture.appending(path: "ignored"))
        let archive = root.appending(path: "fixture.tar.gz")
        let packed = try await SoloistProcess.run(URL(filePath: "/usr/bin/tar"),
                                                 arguments: ["-czf", archive.path, "-C", fixture.path, "soloist", "ignored"])
        check(packed.status == 0)
        let bytes = try Data(contentsOf: archive)
        let installer = SoloistInstaller(files: files, now: { clock.withLock { $0 } }, fetch: { url in
            check(url == SoloistInstaller.address)
            fetched.withLock { $0 += 1 }
            return bytes
        }, probe: { url in
            SoloistBuild(executable: url, version: "fixture", built: Date(timeIntervalSince1970: 2_000_000_000))
        })
        check(try await installer.installed() == nil)
        check(fetched.withLock { $0 } == 0)
        let build = try await installer.install()
        check(build.executable.deletingLastPathComponent().lastPathComponent.count == 64)
        check(!FileManager.default.fileExists(atPath: build.executable.deletingLastPathComponent()
            .appending(path: "ignored").path))
        check(files.ownsExecutable(build.executable.path), "installed executable not owned")
        let cached = try await installer.installed()
        check(cached == build, "cached \(String(describing: cached)), installed \(build)")
        check(try await installer.installed(excluding: [build.executable]) == nil)
        check(try await installer.install() == build)
        try Data("tampered".utf8).write(to: build.executable)
        check(try await installer.installed() == nil)
        check(try await installer.install() == build)
        try FileManager.default.removeItem(at: build.executable.deletingLastPathComponent())
        async let firstInstall = installer.install()
        async let secondInstall = installer.install()
        let duplicate = try await (firstInstall, secondInstall)
        check(duplicate.0 == build && duplicate.1 == build)

        let catalogue = SoloistInstaller(files: files, now: { Date(timeIntervalSince1970: 2_000_000_000) },
                                        fetch: { _ in preconditionFailure("cache lookup fetched") }, probe: { executable in
            let age = TimeInterval(try String(contentsOf: executable, encoding: .utf8)) ?? 1_000
            return SoloistBuild(executable: executable, version: "age-\(age)",
                                built: Date(timeIntervalSince1970: 2_000_000_000 - age * 86_400))
        })
        var newest: URL?
        for age in [89, 15, 1, 90, -2] {
            let data = Data(String(age).utf8)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let folder = files.builds.appending(path: digest)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let executable = folder.appending(path: "soloist")
            try data.write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            if age == 1 { newest = executable }
        }
        check(try await catalogue.installed()?.executable == newest)

        let attempts = Mutex(0)
        let offline = SoloistInstaller(files: files, now: { clock.withLock { $0 } }, fetch: { _ in
            attempts.withLock { $0 += 1 }
            throw SoloistFailure.download
        })
        for attempt in 1...3 {
            do { _ = try await offline.install(); preconditionFailure("offline succeeded") } catch {
                check(error as? SoloistFailure == .download)
            }
            check(attempts.withLock { $0 } == attempt, "a press after a failure didn't try again")
        }
        let refusedFiles = SoloistFiles(root: root.appending(path: "refused"))
        let probes = Mutex(0)
        let refused = SoloistInstaller(files: refusedFiles, now: { clock.withLock { $0 } }, fetch: { _ in bytes }, probe: { url in
            let count = probes.withLock { $0 += 1; return $0 }
            return count == 1 ? nil : SoloistBuild(executable: url, version: "fixture", built: clock.withLock { $0 })
        })
        do { _ = try await refused.install(); preconditionFailure("accepted refused build") } catch {
            check((error as? SoloistFailure)?.reason == .refusedBuild)
        }
        _ = try await refused.install()
        check(probes.withLock { $0 } == 2)
        check(try FileManager.default.contentsOfDirectory(atPath: refusedFiles.root.path)
            .allSatisfy { !$0.hasPrefix("staging-") })

        let cancellations = Mutex(0)
        let cancelFiles = SoloistFiles(root: root.appending(path: "cancelled"))
        let cancellable = SoloistInstaller(files: cancelFiles, fetch: { _ in
            cancellations.withLock { $0 += 1 }
            try await Task.sleep(for: .seconds(60))
            return bytes
        })
        let task = Task { try await cancellable.install() }
        while cancellations.withLock({ $0 }) == 0 { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; preconditionFailure("cancelled install completed") } catch is CancellationError {}
        check(try FileManager.default.contentsOfDirectory(atPath: cancelFiles.root.path)
            .allSatisfy { !$0.hasPrefix("staging-") })
    }

    private static func logChecks() {
        let lines = Mutex<[String]>([])
        let output = SoloistOutput(arguments: ["--api-key", "fixture-secret"], log: { line in
            lines.withLock { $0.append(line) }
        })
        output.consume(Data("bad fixture-".utf8))
        check(lines.withLock { $0.isEmpty })
        output.consume(Data("secret key\nlast fixture-secret".utf8))
        output.finish()
        check(lines.withLock { $0 } == ["soloist: bad <key> key", "soloist: last <key>"])
        output.consume(Data(repeating: 120, count: 65_536))
        output.consume(Data("fixture-secret\nokay\n".utf8))
        check(lines.withLock { $0.last } == "soloist: okay")
        check(!lines.withLock { $0.joined() }.contains("fixture-secret"))
    }

    @MainActor
    private static func leakChecks(files: SoloistFiles) async throws {
        var stored: String?
        let key = SoloistKey(read: { stored }, write: { stored = $0 })
        try key.save("fixture-secret")
        let arguments = files.arguments(key: try key.value()!, deviceName: "fixture")
        let lines = Mutex<[String]>([])
        let launcher = LiveSoloistLauncher(log: { line in lines.withLock { $0.append(line) } })
        let exited = Mutex(false)
        let child = try launcher.launch(URL(filePath: "/bin/sh"), arguments:
            ["-c", "printf '%s\\n' \"$@\"; printf '%s\\n' \"$@\" >&2", "fixture"] + arguments) { _ in
                exited.withLock { $0 = true }
            }
        let deadline = ContinuousClock.now + .seconds(5)
        while !exited.withLock({ $0 }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        check(exited.withLock { $0 }, "fixture child did not exit")
        withExtendedLifetime(child) {}
        let captured = lines.withLock { $0 }
        check(captured.filter { $0 == "soloist: <key>" }.count == 2, "stdout/stderr argv not captured")
        check(!captured.joined().contains("fixture-secret"), "argv leaked to log")
        do {
            _ = try launcher.launch(URL(filePath: "/nonexistent/fixture-secret"), arguments: arguments) { _ in }
            preconditionFailure("missing executable launched")
        } catch {
            check(error as? SoloistFailure == .process, "raw launch error escaped")
            check(!String(describing: error).contains("fixture-secret"), "launch error leaked")
            check(!(error as? SoloistFailure)!.message.contains("fixture-secret"), "failure message leaked")
        }
        check(!lines.withLock { $0.joined() }.contains("fixture-secret"), "failure logged key")
        let suite = "soloist-backup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = ForkSettingsBackupRestore.snapshot(NotchcastPreferences(suiteName: suite))
        check(try key.value() == "fixture-secret", "backup fixture key missing")
        check(!String(describing: snapshot).contains("fixture-secret"), "snapshot leaked key")
        var hostile = snapshot
        hostile["soloist.api-key"] = try key.value()
        let data = try ForkSettingsBackupEngine.encode(hostile, created: .now)
        check(data.range(of: Data("fixture-secret".utf8)) == nil, "backup bytes leaked key")
        let decoded = try ForkSettingsBackupEngine.decode(data)
        check(decoded["soloist.api-key"] == nil, "backup accepted secret field")
        let secretName = /(?i)soloist|spotify|api.?key|secret|token|password/
        for name in ForkSettingsBackupSchema.allowed.keys {
            check(name.firstMatch(of: secretName) == nil, "backup allows secret-shaped key \(name)")
        }
        print("PASS: fixture argv stdout/stderr, launch failure, saved-key snapshot and backup exclusion")
    }

    private static func processChecks() async throws {
        let result = try await SoloistProcess.run(URL(filePath: "/usr/bin/printf"), arguments: ["version fixture"])
        check(result.status == 0 && result.text == "version fixture")
        for _ in 0..<100 {
            let tail = try await SoloistProcess.run(URL(filePath: "/usr/bin/printf"), arguments: ["final output"])
            check(tail.text == "final output")
        }
        let started = ContinuousClock.now
        do {
            _ = try await SoloistProcess.run(URL(filePath: "/bin/sleep"), arguments: ["10"], timeout: .milliseconds(50))
            preconditionFailure("a timeout passed")
        } catch let failure as SoloistFailure { check(failure.message.contains("timed out")) }
        check(ContinuousClock.now - started < .seconds(3))
        let task = Task { try await SoloistProcess.run(URL(filePath: "/bin/sleep"), arguments: ["10"]) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do { _ = try await task.value; preconditionFailure("lost cancellation") } catch is CancellationError {} catch {
            preconditionFailure("wrong cancellation error")
        }
    }
}
