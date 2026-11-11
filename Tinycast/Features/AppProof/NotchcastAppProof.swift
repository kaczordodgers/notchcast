import Foundation

enum NotchcastAppProof {
    static func runIfRequested() -> Bool {
        guard Bundle.main.bundleIdentifier == "app.notchcast.proof",
              let name = ProcessInfo.processInfo.environment["NOTCHCAST_PROOF"] else { return false }
        let checks: [String: @Sendable () async throws -> Void] = [
            "spotify-key": spotifyKey,
            "archive-compress": archiveCompress,
            "archive-fallback": archiveFallback,
        ]
        guard let check = checks[name] else {
            print("PROOF FAIL \(name): unknown check")
            exit(2)
        }
        Task {
            do {
                try await check()
                print("PROOF PASS \(name)")
                exit(0)
            } catch {
                print("PROOF FAIL \(name): \(error)")
                exit(1)
            }
        }
        // The shipped archive flows report progress on the main actor, so the main queue has to run.
        dispatchMain()
    }

    private static func spotifyKey() async throws {
        let key = "abcdefghijklmnopqrstuvwxyz_0123456789"
        guard try SoloistKeyValidation.validated(key + "\n") == key else { throw Failure("key was not trimmed") }
        try await expect(SoloistFailure.invalidKey.detail("refused: hidden character"), "a control character in the key") {
            _ = try SoloistKeyValidation.validated("abc\u{01}" + key)
        }
        let valid = SoloistArchiveRules.Entry(kind: "-", size: 1, name: "soloist")
        guard try SoloistArchiveRules.check([valid]) == ["soloist"] else { throw Failure("valid archive was refused") }
        let bad = SoloistArchiveRules.Entry(kind: "-", size: 1, name: "bad\u{01}")
        let refusal = SoloistFailure.archive.detail("entry - 1 \(bad.name.debugDescription)")
        try await expect(refusal, "a control character in an archive name") {
            _ = try SoloistArchiveRules.check([valid, bad])
        }
    }

    /// Passes only on exactly `expected`: no error fails here, and any other error fails the proof as itself.
    static func expect<Refusal: Error & Equatable>(
        _ expected: Refusal, _ what: String, _ body: () async throws -> Void
    ) async throws {
        do { try await body() } catch let error as Refusal where error == expected { return }
        throw Failure("\(what) was accepted, expected \(expected)")
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) async throws -> Data {
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        let output = try await ProcessRunner.run(.init(executable: URL(filePath: tool), arguments: arguments,
                                                       environment: environment))
        guard output.status == 0 else { throw Failure("\(tool) exited \(output.status)") }
        return output.stdout
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
