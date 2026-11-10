import Darwin
import Foundation

nonisolated enum JobOutput {
    /// Moves `staged` to the first free of `stem + suffix`, `stem (2) + suffix`, …; never replaces a file.
    static func publish(_ staged: URL, in folder: URL, stem: String, suffix: String) throws -> URL {
        for number in 1...10_000 {
            try Task.checkCancellation()
            let target = folder.appending(path: stem + (number == 1 ? "" : " (\(number))") + suffix)
            if renamex_np(staged.path, target.path, UInt32(RENAME_EXCL)) == 0 { return target }
            let code = errno
            if code == EEXIST { continue }
            // Volumes without exclusive rename (exFAT, SMB) still refuse to move onto an existing file.
            guard code == ENOTSUP else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
            do {
                try FileManager.default.moveItem(at: staged, to: target)
                return target
            } catch CocoaError.fileWriteFileExists { continue }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Writes beside the destination first, so only a complete file ever takes the name.
    static func publish(_ data: Data, in folder: URL, stem: String, suffix: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appending(path: ".\(UUID().uuidString).partial")
        defer { try? FileManager.default.removeItem(at: staged) }
        try data.write(to: staged, options: .withoutOverwriting)
        return try publish(staged, in: folder, stem: stem, suffix: suffix)
    }
}
