import Foundation

extension NotchcastAppProof {
    /// Packs a folder with Polish names through the shipped command builder and `ditto`, unpacks it, compares bytes.
    static func archiveCompress() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "notchcast-proof-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let source = root.appending(path: "Zdjęcia")
        try files.createDirectory(at: source.appending(path: "Łódź"), withIntermediateDirectories: true)
        let contents: [String: Data] = [
            "zażółć gęślą jaźń.txt": Data("Polish".utf8), "Łódź/ŚĆIEŻKA.md": Data("nested".utf8), "Łódź/empty": Data(),
        ]
        for (path, data) in contents { try data.write(to: source.appending(path: path)) }
        let output = ArchiveCompression.zip.output(sources: [source]) { files.fileExists(atPath: $0.path) }
        guard output.lastPathComponent == "Zdjęcia.zip" else {
            throw ArchiveProofFailure("first name was \(output.lastPathComponent)")
        }
        try run("/usr/bin/ditto", ArchiveCompression.zip.arguments(sources: [source], output: output))
        let second = ArchiveCompression.zip.output(sources: [source]) { files.fileExists(atPath: $0.path) }
        guard second.lastPathComponent == "Zdjęcia 2.zip" else {
            throw ArchiveProofFailure("taken name gave \(second.lastPathComponent)")
        }
        guard ArchiveCompressor.numbered(root.appending(path: "x.tar.gz"), 2) == "x 2.tar.gz" else {
            throw ArchiveProofFailure("duplicate name lost its multi-part suffix")
        }
        let unpacked = root.appending(path: "out")
        try run("/usr/bin/ditto", ["-x", "-k", output.path, unpacked.path])
        for (path, data) in contents {
            let copy = unpacked.appending(path: "Zdjęcia").appending(path: path)
            guard (try? Data(contentsOf: copy)) == data else { throw ArchiveProofFailure("\(path) differs after round trip") }
        }
        guard (try? run("/usr/bin/ditto", ["-x", "-k", root.appending(path: "missing.zip").path, unpacked.path])) == nil else {
            throw ArchiveProofFailure("a missing archive unpacked")
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ArchiveProofFailure("\(tool) exited \(process.terminationStatus)") }
    }
}

private struct ArchiveProofFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
