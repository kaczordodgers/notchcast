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
        precondition(ArchiveCompression.zip.arguments(sources: [source], output: output)
            == ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, output.path])
        precondition(ArchiveCompression.small.arguments(sources: [source], output: output)
            == ["a", "-t7z", "-mx=9", output.path, "--", source.path])
        let zstd = URL(filePath: "/a tool folder/zstd")
        precondition(ArchiveCompression.fast.arguments(sources: [source], output: output, zstd: zstd)
            == ["--use-compress-program", "\"" + zstd.path + "\" -T0", "-cf", output.path, "-C", root.path, "./fixture"])
        precondition(ArchiveCompression.zip.output(sources: [source], exists: { $0 == output })
            .lastPathComponent == "fixture 2.zip")
        precondition(ArchiveCompression.zip.output(sources: [source, root.appending(path: "other")], exists: { _ in false })
            .lastPathComponent == root.lastPathComponent + ".zip")
        precondition(ArchiveCompression.zip.output(sources: [source, URL(filePath: "/elsewhere/other")], exists: { _ in false })
            .lastPathComponent == "Archive.zip")
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
        let racing = ArchiveCompressor(run: { _, arguments in
            try Data("finished".utf8).write(to: URL(filePath: arguments.last!))
            try Data("other writer".utf8).write(to: output)
            return 0
        })
        let published = try await racing.compress([source], format: .zip)
        precondition(published.lastPathComponent == "fixture 2.zip")
        let original = try Data(contentsOf: output)
        let finished = try Data(contentsOf: published)
        precondition(original == Data("other writer".utf8) && finished == Data("finished".utf8))
        print("PASS: publication EEXIST retries and preserves both finished archive and competing file")
        try files.removeItem(at: output)
        try files.removeItem(at: published)
        try files.createSymbolicLink(atPath: output.path, withDestinationPath: "/nonexistent")
        let writing = ArchiveCompressor(run: { _, arguments in
            try Data("finished".utf8).write(to: URL(filePath: arguments.last!))
            return 0
        })
        let besideLink = try await writing.compress([source], format: .zip)
        precondition(besideLink.lastPathComponent == "fixture 2.zip")
        try files.removeItem(at: output)
        try files.removeItem(at: besideLink)
        let dotted = root.appending(path: "v1.2")
        try files.createDirectory(at: dotted, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: dotted) }
        precondition(ArchiveCompressor.numbered(root.appending(path: "x.tar.gz"), 2) == "x 2.tar.gz")
        precondition(ArchiveCompressor.numbered(root.appending(path: "README"), 2) == "README 2")
        precondition(ArchiveCompressor.numbered(root.appending(path: ".hidden"), 2) == ".hidden 2")
        precondition(ArchiveCompressor.numbered(dotted, 2) == "v1.2 2")
        print("PASS: dangling symlink is a taken name; duplicate names keep multi-part suffixes and folder names")
        let first = root.appending(path: "a/README.md")
        let second = root.appending(path: "b/README.md")
        for url in [first, second] {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(url.path.utf8).write(to: url)
        }
        for format in ArchiveCompression.allCases {
            let sevenzip = ArchiveToolLocator(name: "7zz").locate()
            let compressor = ArchiveToolLocator(name: "zstd").locate()
            if format == .small && sevenzip == nil || format == .fast && compressor == nil {
                print("SKIP: \(format.suffix) real round trips: \(format == .small ? "7zz" : "zstd") not installed")
                continue
            }
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
                tool = sevenzip!
                arguments = ["x", archive.path, "-o" + destination.path]
            case .fast:
                tool = URL(filePath: "/usr/bin/tar")
                arguments = ["--use-compress-program", "\"" + compressor!.path + "\" -d",
                             "-xf", archive.path, "-C", destination.path]
            }
            let extraction = try await ArchiveProcess.run(tool: tool, arguments: arguments)
            precondition(extraction.status == 0)
            let diff = try await ArchiveProcess.run(tool: URL(filePath: "/usr/bin/diff"),
                arguments: ["-r", source.path, destination.appending(path: "fixture").path])
            precondition(diff.status == 0)
            print("PASS: \(format.suffix) Polish filenames, nested directories, empty file; diff -r empty (exit 0)")
            let duplicateArchive = try await ArchiveCompressor().compress([first, second], format: format)
            let duplicateOut = root.appending(path: "duplicates-" + format.rawValue)
            try files.createDirectory(at: duplicateOut, withIntermediateDirectories: false)
            let duplicateArguments: [String]
            switch format {
            case .zip: duplicateArguments = ["-x", "-k", duplicateArchive.path, duplicateOut.path]
            case .small: duplicateArguments = ["x", duplicateArchive.path, "-o" + duplicateOut.path]
            case .fast:
                duplicateArguments = ["--use-compress-program", "\"" + compressor!.path + "\" -d",
                                      "-xf", duplicateArchive.path, "-C", duplicateOut.path]
            }
            let unpacked = try await ArchiveProcess.run(tool: tool, arguments: duplicateArguments)
            precondition(unpacked.status == 0)
            let firstData = try Data(contentsOf: duplicateOut.appending(path: "README.md"))
            let secondData = try Data(contentsOf: duplicateOut.appending(path: "README 2.md"))
            precondition(firstData == Data(first.path.utf8) && secondData == Data(second.path.utf8))
            print("PASS: \(format.suffix) real duplicate-leaf round trip: README.md and README 2.md both preserved")
        }
    }
}
