// notchcast-sources: Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/Soloist*.swift
// notchcast-sources: Tinycast/Features/Music/Service/Soloist*.swift
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Music/Settings/SoloistFailure+Settings.swift
import Darwin
import Foundation

private func check(_ condition: Bool, _ message: String = "check failed", line: UInt = #line) {
    precondition(condition, "\(message), line \(line)")
}

/// Every Spotify Connect failure names its step and the OS's own reason, and never the key.
@main
struct NotchcastSoloistFailuresTest {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "soloist-failures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try keyChecks(root: root)
        try await processChecks()
        try await installChecks(root: root)
        print("PASS: key import, Keychain, tar and process failures name their cause without the key")
    }

    @MainActor
    private static func keyChecks(root: URL) throws {
        var stored: String?
        let key = SoloistKey(read: { stored }, write: { stored = $0 })
        let missing = root.appending(path: "missing-key")
        do { try key.importKey(from: missing); preconditionFailure("imported a missing file") } catch {
            let failure = error as! SoloistFailure
            check(failure.reason == .keyFileUnreadable)
            check(failure.importMessage.contains(missing.path) && failure.importMessage.contains("NSCocoaErrorDomain"),
                  failure.importMessage)
        }
        let folder = root.appending(path: "key-folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do { try key.importKey(from: folder); preconditionFailure("imported a folder") } catch {
            check((error as? SoloistFailure)?.reason == .keyFileUnreadable)
        }
        let spaced = root.appending(path: "spaced-key")
        try Data("fixture secret\n".utf8).write(to: spaced)
        do { try key.importKey(from: spaced); preconditionFailure("imported a key with a space") } catch {
            let failure = error as! SoloistFailure
            check(failure.reason == .invalidKey)
            check(failure.importMessage.hasPrefix(String(localized: "That file has no API key.", table: "Notchcast")))
            check(failure.importMessage.contains(spaced.path) && failure.importMessage.contains("15"), failure.importMessage)
            check(!failure.importMessage.contains("secret") && !failure.message.contains("secret"), "message leaked the key")
            check(failure.importMessage.contains("space or line break"), failure.importMessage)
        }
        // The real key's shape: 37 ASCII letters and digits with one underscore, then a newline.
        let shaped = "Qx7mR2vK9pL4tN8wZ3bH6cJ1dF5gS0_aYeUiO"
        try key.save(shaped + "\n")
        check(stored == shaped, "a pasted key of the real shape was refused")
        let shapedFile = root.appending(path: "shaped-key")
        try Data((shaped + "\n").utf8).write(to: shapedFile)
        stored = nil
        try key.importKey(from: shapedFile)
        check(stored == shaped, "an imported key of the real shape was refused")
        do { try key.save("fixture\u{7}secret"); preconditionFailure("saved a key with a control character") } catch {
            let failure = error as! SoloistFailure
            check(failure.reason == .invalidKey && failure.message.contains("hidden character"), failure.message)
            check(!failure.message.contains("secret"), "message leaked the key")
        }
        check((try? SoloistArchiveRules.check([.init(kind: "-", size: 1, name: "soloist")])) == ["soloist"])
        check((try? SoloistArchiveRules.check([.init(kind: "-", size: 1, name: "soloist"),
                                               .init(kind: "-", size: 1, name: "bad\u{7}name")])) == nil)
        let good = root.appending(path: "good-key")
        try Data("fixture-secret\n".utf8).write(to: good)
        try key.importKey(from: good)
        check(stored == "fixture-secret")

        let locked = SoloistKey(read: { throw KeychainSecretStore.StoreError.keychain(errSecInteractionNotAllowed) },
                                write: { _ in throw KeychainSecretStore.StoreError.keychain(errSecAuthFailed) })
        do { try locked.importKey(from: good); preconditionFailure("saved through a refusing Keychain") } catch {
            let failure = error as! SoloistFailure
            check(failure.reason == .keyNotSaved, "a failed save reads as \(failure.reason)")
            check(failure.importMessage.contains("OSStatus \(errSecAuthFailed)"), failure.importMessage)
            check(!failure.importMessage.contains("fixture-secret"), "message leaked the key")
        }
        do { _ = try locked.value(); preconditionFailure("read through a refusing Keychain") } catch {
            let failure = error as! SoloistFailure
            check(failure.reason == .keyUnavailable && failure.message.contains("OSStatus \(errSecInteractionNotAllowed)"),
                  failure.message)
        }
        do { try locked.remove(); preconditionFailure("removed through a refusing Keychain") } catch {
            check((error as? SoloistFailure)?.reason == .keyNotSaved)
        }
    }

    private static func processChecks() async throws {
        do {
            _ = try await SoloistProcess.run(URL(filePath: "/bin/sleep"), arguments: ["1"], readPipe: { _, _, _ in
                errno = EBADF
                return -1
            })
            preconditionFailure("a failing pipe read passed")
        } catch {
            let failure = error as! SoloistFailure
            check(failure.reason == .process && failure.message.contains("sleep: read:")
                  && failure.message.contains("errno \(EBADF)"), failure.message)
        }
        let waits = SendableCounter()
        let quiet = try await SoloistProcess.run(URL(filePath: "/bin/sh"), arguments: ["-c", "sleep 0.05; printf done"],
                                                 readPipe: { descriptor, buffer, size in
            let count = Darwin.read(descriptor, buffer, size)
            if count < 0 { waits.add() }
            return count
        })
        check(quiet.text == "done" && waits.value > 0, "an empty pipe read stopped the process")
        do {
            _ = try await SoloistProcess.run(URL(filePath: "/nonexistent/tool"), arguments: [])
            preconditionFailure("a missing tool launched")
        } catch {
            let failure = error as! SoloistFailure
            check(failure.reason == .process && failure.message.contains("tool:"), failure.message)
        }
    }

    @MainActor
    private static func installChecks(root: URL) async throws {
        let files = SoloistFiles(root: root.appending(path: "Application Support/soloist"))
        let garbage = SoloistInstaller(files: files, fetch: { _ in Data("not an archive".utf8) }, probe: { _ in nil })
        do { _ = try await garbage.install(); preconditionFailure("installed garbage") } catch {
            let failure = error as! SoloistFailure
            check(failure.reason == .unpack, "unpack failure reads as \(failure.reason)")
            check(failure.message.contains("tar -tvzf exited") && failure.message.contains("tar:"), failure.message)
        }
        let full = SoloistInstaller(files: files, fetch: { _ in throw CocoaError(.fileWriteOutOfSpace) })
        do { _ = try await full.install(); preconditionFailure("installed without bytes") } catch {
            let failure = error as! SoloistFailure
            check(failure.reason == .filesystem && failure.message.contains("NSCocoaErrorDomain 640"), failure.message)
        }
        do {
            _ = try SoloistArchiveRules.entries("garbled listing line")
            preconditionFailure("parsed a garbled listing")
        } catch {
            check((error as? SoloistFailure)?.message.contains("garbled listing line") == true)
        }
        check(try FileManager.default.contentsOfDirectory(atPath: files.root.path).allSatisfy { !$0.hasPrefix("staging-") })
    }
}

private final class SendableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}
