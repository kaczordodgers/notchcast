import Darwin
import Foundation

struct CleanHistoryRestore: Sendable {
    let originalRoots: [URL]
    let trashRoots: [URL]
    let log: CleanHistoryStore
    let now: @Sendable () -> Date

    func restore(_ entry: CleanHistoryEntry) throws {
        let result = Result { try move(entry) }
        let status: CleanHistoryEntry.Status
        switch result {
        case .success: status = .restored
        case .failure: status = .failed
        }
        try log.append(CleanHistoryEntry(time: now(), mode: "restore", size: entry.size,
                                        status: status,
                                        originalPath: entry.originalPath, trashPath: entry.trashPath))
        try result.get()
    }

    private func move(_ entry: CleanHistoryEntry) throws {
        guard entry.status == .trashed else { throw CleanHistoryError.invalidPath }
        let original = try validated(entry.originalPath, roots: originalRoots)
        let trash = try validated(entry.trashPath, roots: trashRoots)
        let source = try directory(trash.deletingLastPathComponent(), missing: .trashMissing)
        defer { close(source) }
        let destination = try directory(original.deletingLastPathComponent(), missing: .parentMissing)
        defer { close(destination) }
        var info = stat()
        guard fstatat(source, trash.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw CleanHistoryError.trashMissing
        }
        guard info.st_mode & S_IFMT != S_IFLNK else { throw CleanHistoryError.symbolicLink }
        guard renameatx_np(source, trash.lastPathComponent, destination, original.lastPathComponent,
                          UInt32(RENAME_EXCL)) == 0 else {
            switch errno {
            case EEXIST, ENOTEMPTY: throw CleanHistoryError.destinationExists
            case ENOENT: throw CleanHistoryError.trashMissing
            default: throw CleanHistoryError.system(errno)
            }
        }
    }

    private func validated(_ path: String, roots: [URL]) throws -> URL {
        guard path.hasPrefix("/"), !path.utf8.contains(0),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw CleanHistoryError.invalidPath
        }
        let normalized = "/" + path.split(separator: "/").joined(separator: "/")
        guard roots.contains(where: {
            let root = "/" + $0.path.split(separator: "/").joined(separator: "/")
            return normalized.hasPrefix(root + "/")
        }) else {
            throw CleanHistoryError.invalidPath
        }
        return URL(fileURLWithPath: path)
    }

    private func directory(_ url: URL, missing: CleanHistoryError) throws -> Int32 {
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw CleanHistoryError.system(errno) }
        for component in url.path.split(separator: "/") {
            let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            close(descriptor)
            guard next >= 0 else { throw missing }
            descriptor = next
        }
        return descriptor
    }
}
