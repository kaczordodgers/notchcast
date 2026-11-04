import CryptoKit
import Foundation

nonisolated enum DistillFileAccess {
    static let maximumBytes = 32 * 1024 * 1024

    struct Identity: Equatable {
        let size: Int
        let modified: Date
        let inode: UInt64
    }

    struct Snapshot: Equatable {
        let identity: Identity
        let hash: String
    }

    static func check(_ url: URL, in root: URL, allowingRoot: Bool = false) throws {
        if allowingRoot, url.path == root.path { return }
        guard url.path.hasPrefix(root.path + "/") else { throw DistillConversion.Failure.unsafePath }
        var path = url
        while path.path != root.path {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw DistillConversion.Failure.unsafePath
            }
            path.deleteLastPathComponent()
        }
        guard root.resolvingSymlinksInPath() == root else { throw DistillConversion.Failure.unsafePath }
    }

    static func identity(_ source: URL) throws -> Identity {
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? Int,
            let modified = attributes[.modificationDate] as? Date,
            let inode = attributes[.systemFileNumber] as? UInt64
        else { throw DistillConversion.Failure.unsafePath }
        guard size <= maximumBytes else { throw DistillConversion.Failure.tooLarge }
        return Identity(size: size, modified: modified, inode: inode)
    }

    static func snapshot(_ source: URL, in root: URL) throws -> Snapshot {
        try check(source, in: root)
        let before = try identity(source)
        let stream = try FileHandle(forReadingFrom: source)
        defer { try? stream.close() }
        var digest = SHA256()
        while let data = try stream.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            digest.update(data: data)
        }
        try check(source, in: root)
        guard try identity(source) == before else { throw DistillConversion.Failure.sourceChanged }
        return Snapshot(identity: before, hash: digest.finalize().map { String(format: "%02x", $0) }.joined())
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func text(_ source: URL) throws -> String {
        let data = try Data(contentsOf: source)
        guard !data.contains(0), let text = String(bytes: data, encoding: .utf8) else {
            throw DistillConversion.Failure.unreadable
        }
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    static func output(for source: URL, matching hash: String, in root: URL) throws -> URL {
        let candidates = [source.deletingPathExtension().appendingPathExtension("md"), source.appendingPathExtension("md")]
        for index in 0..<10_000 {
            let candidate = index < 2 ? candidates[index] : source.deletingLastPathComponent()
                .appendingPathComponent(source.lastPathComponent + " - Converted \(index).md")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            if let existing = try? snapshot(candidate, in: root), existing.hash == hash { return candidate }
        }
        throw DistillConversion.Failure.noOutputName
    }
}
