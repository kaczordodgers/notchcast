import Foundation
import Darwin

enum MacUpdateLock {
    static func path(for brew: String) -> String {
        URL(filePath: brew).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "var/homebrew/locks/update").path
    }

    static func isHeld(at path: String) -> Bool {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return errno != ENOENT }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return true }
        _ = flock(descriptor, LOCK_UN)
        return false
    }
}
