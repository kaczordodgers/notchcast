import Foundation

extension NotchcastAppProof {
    /// Routes by name, then unpacks real `tar.bz2` files through the shipped runner: one good, one escaping.
    static func archiveFallback() async throws {
        let routes: [String: ArchiveEngineRoute?] = [
            "a.zip": .hatchzip, "a.tar.gz": .hatchzip, "a.7z": .hatchzip, "a.tar.xz": .bsdtar, "a.tar.bz2": .bsdtar,
            "a.gz": .bsdtar, "a.iso": .bsdtar, "a.tar.zst": .zstd, "a.zst": .zstd, "a.sit": .xad, "a.docx": nil,
        ]
        for (name, engine) in routes where ArchiveEngineRoute.route(URL(filePath: "/tmp/\(name)")) != engine {
            throw Failure("\(name) routed wrongly")
        }
        guard ArchiveEngineRoute.route(URL(filePath: "/tmp/a.zip"), windowsZIP: true) == .xad,
              !ArchiveZIPEncoding.inspect(Data(repeating: 0x50, count: 4096)).requiresUnar else {
            throw Failure("ZIP name encoding detection")
        }
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "notchcast-proof-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let source = root.appending(path: "Łódź")
        let inbox = root.appending(path: "in")
        let refused = root.appending(path: "refused")
        for folder in [source, inbox, refused] { try files.createDirectory(at: folder, withIntermediateDirectories: true) }
        let data = Data("zażółć gęślą jaźń".utf8)
        try data.write(to: source.appending(path: "gęś.txt"))
        try data.write(to: root.appending(path: "x.txt"))
        let zip = root.appending(path: "mac.zip")
        try await run("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, zip.path])
        guard !ArchiveZIPEncoding.inspect(try Data(contentsOf: zip)).requiresUnar else {
            throw Failure("a Mac-made Polish zip left hatchzip")
        }
        let tarball = inbox.appending(path: "a.tar.bz2")
        try await run("/usr/bin/tar", ["-cjf", tarball.path, "-C", root.path, "Łódź"])
        let output = try await ArchiveExtractionRunner().extract(tarball)
        guard output.lastPathComponent == "Łódź", try Data(contentsOf: output.appending(path: "gęś.txt")) == data else {
            throw Failure("tar.bz2 round trip differs at \(output.path)")
        }
        let escaping = refused.appending(path: "escaping.tar.bz2")
        try await run("/usr/bin/tar", ["-cjf", escaping.path, "-C", source.path, "../x.txt"])
        try await expect(ArchiveFailure.unsafePath("../x.txt"), "a traversal member") {
            _ = try await ArchiveExtractionRunner().extract(escaping)
        }
        guard try files.contentsOfDirectory(atPath: refused.path) == ["escaping.tar.bz2"] else {
            throw Failure("a refused archive left files beside it")
        }
    }
}
