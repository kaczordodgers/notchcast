import Foundation

enum NotchcastAppProof {
    static func runIfRequested() -> Bool {
        guard Bundle.main.bundleIdentifier == "app.notchcast.proof",
              let name = ProcessInfo.processInfo.environment["NOTCHCAST_PROOF"] else { return false }
        let checks: [String: () throws -> Void] = [
            "spotify-key": spotifyKey,
            "archive-compress": archiveCompress,
        ]
        guard let check = checks[name] else {
            print("PROOF FAIL \(name): unknown check")
            exit(2)
        }
        do {
            try check()
            print("PROOF PASS \(name)")
            exit(0)
        } catch {
            print("PROOF FAIL \(name): \(error)")
            exit(1)
        }
    }

    private static func spotifyKey() throws {
        let key = "abcdefghijklmnopqrstuvwxyz_0123456789"
        guard try SoloistKeyValidation.validated(key + "\n") == key else {
            throw Failure(detail: "key was not trimmed")
        }
        guard (try? SoloistKeyValidation.validated("abc\u{01}" + key)) == nil else {
            throw Failure(detail: "key accepted a control character")
        }
        let valid = SoloistArchiveRules.Entry(kind: "-", size: 1, name: "soloist")
        guard try SoloistArchiveRules.check([valid]) == ["soloist"] else {
            throw Failure(detail: "valid archive was refused")
        }
        let bad = SoloistArchiveRules.Entry(kind: "-", size: 1, name: "bad\u{01}")
        guard (try? SoloistArchiveRules.check([valid, bad])) == nil else {
            throw Failure(detail: "archive accepted a control character")
        }
    }

    private struct Failure: Error, CustomStringConvertible {
        let detail: String
        var description: String { detail }
    }
}
