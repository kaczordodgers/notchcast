import Darwin
import Foundation

enum SudoTouchID {
    enum Failure: Error { case unsafeFile, io }

    static func run(enabled: Bool) throws {
        let path = "/etc/pam.d/sudo_local"
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        let original: String?
        if descriptor < 0 {
            guard errno == ENOENT else { throw Failure.unsafeFile }
            original = nil
        } else {
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_uid == 0,
                  info.st_mode & S_IFMT == S_IFREG else { throw Failure.unsafeFile }
            guard let text = String(data: try handle.readToEnd() ?? Data(), encoding: .utf8) else {
                throw Failure.io
            }
            original = text
        }
        let sudo = try String(contentsOfFile: "/etc/pam.d/sudo", encoding: .utf8)
        guard let replacement = try TouchIDPolicy.replacement(
            sudo: sudo, local: original, enabled: enabled) else { return }
        var template = Array("/etc/pam.d/.sudo_local.XXXXXX".utf8CString)
        let temporary = mkstemp(&template)
        guard temporary >= 0 else { throw Failure.io }
        defer {
            close(temporary)
            unlink(template)
        }
        let data = Data(replacement.utf8)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(temporary, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.io }
                offset += count
            }
        }
        guard fchown(temporary, 0, 0) == 0, fchmod(temporary, 0o444) == 0,
              fsync(temporary) == 0, rename(template, path) == 0 else { throw Failure.io }
    }
}
