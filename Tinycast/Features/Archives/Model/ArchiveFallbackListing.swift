import Foundation

nonisolated enum ArchiveFallbackListing {
    static func bsdtar(_ data: Data) throws -> ArchiveListing {
        guard data.count <= 16_000_000, let text = String(data: data, encoding: .utf8) else {
            throw ArchiveFailure.invalidListing
        }
        let expression = try Regex(#"^([dlh-])[rwxstST-]{9}[+@]?\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\d+\s+[\d:]+\s(.*)$"#)
        var entries: [ArchiveListing.Entry] = []
        var total: Int64 = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast(text.hasSuffix("\n") ? 1 : 0) {
            guard let match = try expression.wholeMatch(in: String(line)),
                  let kind = match[1].substring, let size = match[2].substring.flatMap({ Int64($0) }),
                  var path = match[3].substring.map(String.init), !path.isEmpty,
                  kind != "h" else { throw ArchiveFailure.invalidListing }
            let link = kind == "l"
            if link {
                let parts = path.components(separatedBy: " -> ")
                guard parts.count == 2 else { throw ArchiveFailure.invalidListing }
                _ = try ArchiveRules.components(parts[1])
                path = parts[0]
            }
            entries.append(.init(path: path, isDirectory: kind == "d", isSymlink: link))
            guard entries.count <= 100_000 else { throw ArchiveFailure.tooManyEntries }
            let addition = total.addingReportingOverflow(kind == "-" ? size : 0)
            guard !addition.overflow else { throw ArchiveFailure.invalidListing }
            total = addition.partialValue
        }
        return ArchiveListing(entries: entries, totalBytes: total)
    }

    static func lsar(_ data: Data) throws -> (listing: ArchiveListing, encoding: String?) {
        struct Document: Decodable {
            let lsarFormatVersion: Int
            let lsarContents: [Entry]
            let lsarError: Int?
            let lsarEncoding: String?
        }
        struct Entry: Decodable {
            let XADFileName: String
            let XADFileSize: Int64?
            let XADIsDirectory: Bool?
            let XADIsLink: Bool?
            let XADIsHardLink: Bool?
            let XADIsResourceFork: Bool?
            let XADIsEncrypted: Bool?
            let XADIsCorrupted: Bool?
            let XADIsCharacterDevice: Bool?
            let XADIsBlockDevice: Bool?
            let XADIsFIFO: Bool?
            let XADLinkDestination: String?
        }
        guard data.count <= 16_000_000 else { throw ArchiveFailure.invalidListing }
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else {
            throw ArchiveFailure.invalidListing
        }
        guard document.lsarFormatVersion == 2, document.lsarError == nil || document.lsarError == 0 else {
            throw ArchiveFailure.invalidListing
        }
        guard document.lsarContents.count <= 100_000 else { throw ArchiveFailure.tooManyEntries }
        let dataPaths = Set(document.lsarContents.filter {
            $0.XADIsResourceFork != true && $0.XADIsDirectory != true && $0.XADIsLink != true
        }.map(\.XADFileName))
        var forks = Set<String>()
        var entries: [ArchiveListing.Entry] = []
        var total: Int64 = 0
        for entry in document.lsarContents {
            if entry.XADIsEncrypted == true { throw ArchiveFailure.passwordRequired }
            if entry.XADIsCorrupted == true { throw ArchiveFailure.damagedArchive }
            guard entry.XADIsHardLink != true, entry.XADIsCharacterDevice != true,
                  entry.XADIsBlockDevice != true, entry.XADIsFIFO != true else {
                throw ArchiveFailure.unsafePath(entry.XADFileName)
            }
            let directory = entry.XADIsDirectory == true
            let link = entry.XADIsLink == true
            if link {
                guard let target = entry.XADLinkDestination else { throw ArchiveFailure.invalidListing }
                _ = try ArchiveRules.components(target)
            }
            guard let size = entry.XADFileSize ?? (directory || link ? 0 : nil), size >= 0 else {
                throw ArchiveFailure.invalidListing
            }
            if entry.XADIsResourceFork == true {
                guard !directory, !link, forks.insert(entry.XADFileName).inserted else {
                    throw ArchiveFailure.collision(entry.XADFileName)
                }
                if !dataPaths.contains(entry.XADFileName) {
                    entries.append(.init(path: entry.XADFileName, isDirectory: false, isSymlink: false))
                }
            } else {
                entries.append(.init(path: entry.XADFileName, isDirectory: directory, isSymlink: link))
            }
            let addition = total.addingReportingOverflow(directory || link ? 0 : size)
            guard !addition.overflow else { throw ArchiveFailure.invalidListing }
            total = addition.partialValue
        }
        return (ArchiveListing(entries: entries, totalBytes: total), document.lsarEncoding)
    }

    static func stream(_ archive: URL, bytes: Int64) -> ArchiveListing {
        ArchiveListing(entries: [.init(path: archive.deletingPathExtension().lastPathComponent,
                                      isDirectory: false, isSymlink: false)], totalBytes: bytes)
    }
}
