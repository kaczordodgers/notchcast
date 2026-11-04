import Foundation

nonisolated struct ArchiveListing: Sendable {
    struct Entry: Sendable {
        let path: String
        let isDirectory: Bool
        let isSymlink: Bool
    }

    private(set) var entries: [Entry] = []
    private(set) var totalBytes: Int64?
    private var pending = Data()
    private var capturedBytes = 0

    mutating func feed(_ data: Data) throws {
        capturedBytes += data.count
        guard capturedBytes <= 16_000_000 else { throw ArchiveFailure.invalidListing }
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            guard let line = String(bytes: pending[..<newline], encoding: .utf8) else {
                throw ArchiveFailure.invalidListing
            }
            pending.removeSubrange(...newline)
            try parse(line)
        }
        guard pending.count < 65_536 else { throw ArchiveFailure.invalidListing }
    }

    mutating func finish() throws {
        if !pending.isEmpty {
            guard let line = String(bytes: pending, encoding: .utf8) else { throw ArchiveFailure.invalidListing }
            try parse(line)
        }
        pending.removeAll()
        guard totalBytes != nil else { throw ArchiveFailure.invalidListing }
    }

    private mutating func parse(_ line: String) throws {
        if line == "      Size  Name" || line.isEmpty { return }
        let fields = line.components(separatedBy: ", ")
        if !line.dropFirst(10).hasPrefix("  "), fields.count == 3,
           fields[0].hasSuffix(" entry") || fields[0].hasSuffix(" entries") {
            guard let count = Int(fields[0].split(separator: " ")[0]),
                  count == entries.count, fields[1].hasSuffix(" uncompressed"),
                  let bytes = Self.bytes(String(fields[1].dropLast(" uncompressed".count))) else {
                throw ArchiveFailure.invalidListing
            }
            totalBytes = bytes
            return
        }
        guard totalBytes == nil, line.count > 12, line.dropFirst(10).hasPrefix("  ") else {
            throw ArchiveFailure.invalidListing
        }
        var name = String(line.dropFirst(12))
        let link = name.hasSuffix(" (symlink)")
        if link { name.removeLast(" (symlink)".count) }
        entries.append(Entry(path: name, isDirectory: name.hasSuffix("/"), isSymlink: link))
        if entries.count > 100_000 { throw ArchiveFailure.tooManyEntries }
    }

    private static func bytes(_ text: String) -> Int64? {
        let parts = text.split(separator: " ")
        let factors: [String: Double] = ["B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12]
        guard parts.count == 2, let value = Double(parts[0]), let factor = factors[String(parts[1])],
              value.isFinite, value >= 0, value * factor < Double(Int64.max) else { return nil }
        return Int64((value * factor).rounded(.up))
    }
}
