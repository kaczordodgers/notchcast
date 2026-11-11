import Foundation

extension NotchcastAppProof {
    /// Packs Polish names through the shipped compress flow; `ditto` only unpacks, as the independent reader.
    static func archiveCompress() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "notchcast-proof-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let source = root.appending(path: "Zdjęcia")
        try files.createDirectory(at: source.appending(path: "Łódź"), withIntermediateDirectories: true)
        let contents: [String: Data] = [
            "zażółć gęślą jaźń.txt": Data("Polish".utf8), "Łódź/ŚĆIEŻKA.md": Data("nested".utf8), "Łódź/empty": Data(),
        ]
        for (path, data) in contents { try data.write(to: source.appending(path: path)) }
        let compressor = ArchiveCompressor()
        let first = try await compressor.compress([source], format: .zip)
        let second = try await compressor.compress([source], format: .zip)
        guard first.lastPathComponent == "Zdjęcia.zip", second.lastPathComponent == "Zdjęcia (2).zip" else {
            throw Failure("archives were named \(first.lastPathComponent) and \(second.lastPathComponent)")
        }
        let unpacked = root.appending(path: "out")
        try await run("/usr/bin/ditto", ["-x", "-k", first.path, unpacked.path])
        for (path, data) in contents {
            guard try Data(contentsOf: unpacked.appending(path: "Zdjęcia").appending(path: path)) == data else {
                throw Failure("\(path) differs after round trip")
            }
        }
        var twins: [URL] = []
        for folder in ["a", "b"] {
            let twin = root.appending(path: folder).appending(path: "x.tar.gz")
            try files.createDirectory(at: twin.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(folder.utf8).write(to: twin)
            twins.append(twin)
        }
        let pair = root.appending(path: "pair")
        try await run("/usr/bin/ditto", ["-x", "-k", compressor.compress(twins, format: .zip).path, pair.path])
        guard try Data(contentsOf: pair.appending(path: "x.tar.gz")) == Data("a".utf8),
              try Data(contentsOf: pair.appending(path: "x (2).tar.gz")) == Data("b".utf8) else {
            throw Failure("same-named sources lost a copy or its multi-part suffix")
        }
        try await expect(ArchiveFailure.filesystem("selection"), "a missing source") {
            _ = try await compressor.compress([root.appending(path: "missing")], format: .zip)
        }
    }
}
