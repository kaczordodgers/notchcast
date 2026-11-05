import Foundation

@main struct ArchiveCompressionTests {
    static func main() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let source = root.appending(path: "fixture")
        try files.createDirectory(at: source.appending(path: "Łódź/nested"), withIntermediateDirectories: true)
        try Data("Polish content".utf8).write(to: source.appending(path: "zażółć gęślą jaźń.txt"))
        try Data("nested".utf8).write(to: source.appending(path: "Łódź/ŚĆIEŻKA.md"))
        try Data().write(to: source.appending(path: "Łódź/nested/empty"))
        let output = root.appending(path: "fixture.zip")
        precondition(ArchiveCompression.zip.arguments(sources: [source], output: output) == ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, output.path])
        precondition(ArchiveCompression.small.arguments(sources: [source], output: output) == ["a", "-t7z", "-mx=9", output.path, "--", source.path])
        let zstd = URL(filePath: "/opt/homebrew/bin/zstd")
        precondition(ArchiveCompression.fast.arguments(sources: [source], output: output, zstd: zstd) == ["--use-compress-program", zstd.path + " -T0", "-cf", output.path, "-C", root.path, "./fixture"])
        precondition(ArchiveCompression.zip.output(sources: [source], exists: { $0 == output }).lastPathComponent == "fixture 2.zip")
        precondition(ArchiveCompression.zip.output(sources: [source, root.appending(path: "other")], exists: { _ in false }).lastPathComponent == root.lastPathComponent + ".zip")
        precondition(ArchiveCompression.zip.output(sources: [source, URL(filePath: "/elsewhere/other")], exists: { _ in false }).lastPathComponent == "Archive.zip")
        let failing = ArchiveCompressor(run: { _, arguments in
            try Data().write(to: URL(filePath: arguments.last!))
            return 1
        })
        do {
            _ = try await failing.compress([source], format: .zip)
            preconditionFailure("failure expected")
        } catch ArchiveFailure.compressionFailed(1) {}
        let remaining = try files.contentsOfDirectory(atPath: root.path)
        precondition(remaining == ["fixture"])
        let cancelling = ArchiveCompressor(run: { _, arguments in
            try Data().write(to: URL(filePath: arguments.last!))
            throw CancellationError()
        })
        do {
            _ = try await cancelling.compress([source], format: .zip)
            preconditionFailure("cancellation expected")
        } catch is CancellationError {}
        let afterCancel = try files.contentsOfDirectory(atPath: root.path)
        precondition(afterCancel == ["fixture"])
        print("PASS: exact commands, no password arguments, collision/multiple-item names, failure cleanup")
        for format in ArchiveCompression.allCases {
            let archive = try await ArchiveCompressor().compress([source], format: format)
            let destination = root.appending(path: "out-" + format.rawValue)
            try files.createDirectory(at: destination, withIntermediateDirectories: false)
            let tool: URL
            let arguments: [String]
            switch format {
            case .zip:
                tool = URL(filePath: "/usr/bin/ditto")
                arguments = ["-x", "-k", archive.path, destination.path]
            case .small:
                tool = URL(filePath: "/opt/homebrew/bin/7zz")
                arguments = ["x", archive.path, "-o" + destination.path]
            case .fast:
                tool = URL(filePath: "/usr/bin/tar")
                arguments = ["--use-compress-program", zstd.path + " -d", "-xf", archive.path, "-C", destination.path]
            }
            let extraction = try await ArchiveProcess.run(tool: tool, arguments: arguments)
            precondition(extraction.status == 0)
            let diff = try await ArchiveProcess.run(tool: URL(filePath: "/usr/bin/diff"), arguments: ["-r", source.path, destination.appending(path: "fixture").path])
            precondition(diff.status == 0)
            print("PASS: \(format.suffix) Polish filenames, nested directories, empty file; diff -r empty (exit 0)")
        }
    }
}
