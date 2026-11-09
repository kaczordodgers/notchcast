import Foundation

extension NotchcastAppProof {
    static func archiveFallback() throws {
        let routes: [String: ArchiveEngineRoute?] = [
            "a.zip": .hatchzip, "a.tar.gz": .hatchzip, "a.7z": .hatchzip, "a.tar.xz": .bsdtar, "a.tar.bz2": .bsdtar,
            "a.gz": .bsdtar, "a.iso": .bsdtar, "a.tar.zst": .zstd, "a.zst": .zstd, "a.sit": .xad, "a.docx": nil,
        ]
        for (name, engine) in routes where ArchiveEngineRoute.route(URL(filePath: "/tmp/\(name)")) != engine {
            throw ArchiveFallbackProofFailure("\(name) routed wrongly")
        }
        guard ArchiveEngineRoute.route(URL(filePath: "/tmp/a.zip"), windowsZIP: true) == .xad,
              !ArchiveZIPEncoding.inspect(Data(repeating: 0x50, count: 4096)).requiresUnar else {
            throw ArchiveFallbackProofFailure("ZIP name encoding detection")
        }
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "notchcast-proof-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let source = root.appending(path: "Łódź")
        try files.createDirectory(at: source, withIntermediateDirectories: true)
        let data = Data("zażółć gęślą jaźń".utf8)
        try data.write(to: source.appending(path: "gęś.txt"))
        let zip = root.appending(path: "mac.zip")
        try shell("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, zip.path])
        guard !ArchiveZIPEncoding.inspect(try Data(contentsOf: zip)).requiresUnar else {
            throw ArchiveFallbackProofFailure("a Mac-made Polish zip left hatchzip")
        }
        let tarball = root.appending(path: "a.tar.bz2")
        try shell("/usr/bin/tar", ["-cjf", tarball.path, "-C", root.path, "Łódź"])
        let listing = try ArchiveFallbackListing.bsdtar(shell("/usr/bin/bsdtar", ["-tvf", tarball.path]))
        try ArchiveRules.validate(listing, archiveBytes: Int64(Data(contentsOf: tarball).count))
        let unsafe = Data("-rw-r--r--  0 user group 1 Jan 1 2026 ../x\n".utf8)
        do {
            try ArchiveRules.validate(ArchiveFallbackListing.bsdtar(unsafe), archiveBytes: 1)
            throw ArchiveFallbackProofFailure("a traversal member passed validation")
        } catch ArchiveFailure.unsafePath("../x") {
        }
        let out = root.appending(path: "out")
        try files.createDirectory(at: out, withIntermediateDirectories: true)
        try shell("/usr/bin/bsdtar", ["-xf", tarball.path, "-C", out.path])
        guard (try? Data(contentsOf: out.appending(path: "Łódź/gęś.txt"))) == data else {
            throw ArchiveFallbackProofFailure("tar.bz2 round trip differs")
        }
    }

    @discardableResult
    private static func shell(_ tool: String, _ arguments: [String]) throws -> Data {
        let output = try ProcessRunner.runBlocking(.init(executable: URL(filePath: tool), arguments: arguments))
        guard output.status == 0 else { throw ArchiveFallbackProofFailure("\(tool) exited \(output.status)") }
        return output.stdout
    }
}

private struct ArchiveFallbackProofFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
