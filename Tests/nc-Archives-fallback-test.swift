import Foundation

@main
struct ArchivesFallbackTest {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    static func refuses(_ expected: ArchiveFailure, _ body: () throws -> Void) {
        do {
            try body()
            fatalError("Accepted \(expected)")
        } catch {
            expect(error as? ArchiveFailure == expected, "Expected \(expected), got \(error)")
        }
    }

    @MainActor static func main() async throws {
        routing()
        zipNames()
        try parsers()
        let root = FileManager.default.temporaryDirectory.appending(path: "archive-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let savedParents = UserDefaults.standard.stringArray(forKey: "archiveRecoveryParents")
        UserDefaults.standard.set([], forKey: "archiveRecoveryParents")
        defer {
            try? ArchiveFiles.removeStaging(root)
            UserDefaults.standard.set(savedParents, forKey: "archiveRecoveryParents")
        }
        try await fakeXAD(root)
        try await realTools(root)
        print("PASS: fallback routing, ZIP encoding, parsers, validation, keep-only jobs and tool isolation")
    }

    static func routing() {
        let table: [(ArchiveEngineRoute, [String])] = [
            (.hatchzip, ["zip", "7z", "rar", "tar", "tgz", "tar.gz", "001", "r00", "r99"]),
            (.bsdtar, ["tar.xz", "txz", "tar.bz2", "tbz2", "gz", "xz", "bz2", "iso", "cab", "pkg", "xar", "cpio"]),
            (.zstd, ["zst", "tar.zst", "tzst"]),
            (.xad, ["sit", "sitx", "lzh", "lha", "arj", "z", "arc", "zoo"])
        ]
        for (route, suffixes) in table {
            for suffix in suffixes {
                let url = URL(fileURLWithPath: "/fixture/sample.\(suffix)")
                expect(ArchiveEngineRoute.route(url) == route, "Routing .\(suffix)")
                expect(ArchiveEngineRoute.route(URL(fileURLWithPath: url.path.uppercased())) == route, "Case .\(suffix)")
                expect(ArchiveFormat.accepts(url), "Accepted .\(suffix)")
                expect(ArchiveFormat.baseName(url) == "sample", "Stem .\(suffix)")
            }
        }
        expect(ArchiveEngineRoute.route(URL(fileURLWithPath: "/a.txt")) == nil, "Unknown format")
        expect(!ArchiveFormat.defaultTypeIdentifiers.contains("public.iso-image"), "ISO never claimed")
        expect(!ArchiveFormat.defaultTypeIdentifiers.contains("com.apple.installer-package-archive"), "PKG never claimed")
        expect(ArchiveFormat.typeIdentifiers.contains("public.iso-image"), "ISO Open With")
        expect(ArchiveFormat.typeIdentifiers.contains("com.apple.installer-package-archive"), "PKG Open With")
        print("PASS: every routing extension, case-insensitive matching, tar.gz hatchzip, ISO/PKG Open With only")
    }

    static func zip(_ name: [UInt8], flags: UInt16) -> Data {
        var result = Data(repeating: 0, count: 46)
        result.replaceSubrange(0..<4, with: [0x50, 0x4b, 0x01, 0x02])
        result[8] = UInt8(truncatingIfNeeded: flags)
        result[9] = UInt8(truncatingIfNeeded: flags >> 8)
        result[28] = UInt8(name.count)
        result.append(contentsOf: name)
        var end = Data(repeating: 0, count: 22)
        end.replaceSubrange(0..<4, with: [0x50, 0x4b, 0x05, 0x06])
        end[8] = 1
        end[10] = 1
        end[12] = UInt8(result.count)
        result.append(end)
        return result
    }

    static func zipNames() {
        expect(!ArchiveZIPEncoding.inspect(zip(Array("Zdjęcia/é.txt".utf8), flags: 0)).requiresUnar,
               "Flagless valid UTF-8 stays hatchzip")
        expect(!ArchiveZIPEncoding.inspect(zip([0xc4, 0x85], flags: 0x800)).requiresUnar, "UTF-8 flag stays hatchzip")
        expect(!ArchiveZIPEncoding.inspect(zip(Array("ascii.txt".utf8), flags: 0)).requiresUnar, "ASCII stays hatchzip")
        expect(ArchiveZIPEncoding.inspect(zip([0xa5, 0x86, 0x2e, 0x74], flags: 0)).requiresUnar, "High bytes use XAD")
        expect(ArchiveZIPEncoding.inspect(zip([0xa5, 0x86, 0xa9, 0x88], flags: 0)).encoding == "IBM852", "CP852 hint")
        expect(ArchiveZIPEncoding.inspect(zip([0xb9, 0xe6, 0xea, 0xb3], flags: 0)).encoding == "windows-1250", "CP1250 hint")
        expect(ArchiveZIPEncoding.inspect(zip([0xe9, 0xe8, 0xe7], flags: 0)).encoding == nil, "Other names use XAD detection")
        expect(ArchiveZIPEncoding.inspect(zip([0xa5], flags: 0)).encoding == nil, "Ambiguous bytes use XAD detection")
        expect(ArchiveEngineRoute.route(URL(fileURLWithPath: "/windows.zip"), windowsZIP: true) == .xad, "ZIP routing")
        for count in 0..<68 {
            expect(!ArchiveZIPEncoding.inspect(Data(repeating: 0, count: count)).requiresUnar, "Truncated ZIP \(count)")
        }
        var truncated = zip([0xa5], flags: 0)
        truncated[28] = 255
        expect(!ArchiveZIPEncoding.inspect(truncated).requiresUnar, "Malformed central directory")
        var payload = Data([0x50, 0x4b, 0x01, 0x02, 0xff])
        payload.append(zip(Array("ascii".utf8), flags: 0))
        expect(!ArchiveZIPEncoding.inspect(payload).requiresUnar, "No signature scan of local payload")
        print("PASS: central-directory UTF-8 flag, unset ASCII/high bytes, malformed and truncated ZIPs")
    }

    static func parsers() throws {
        let tar = Data("""
        drwxr-xr-x  0 0 0 0 Jan  1  1970 Folder/
        -rw-r--r--  0 0 0 12 Jan  1 12:00 Folder/Polish name.txt
        lrwxr-xr-x  0 0 0 0 Jan  1 12:00 Folder/link -> Polish name.txt

        """.utf8)
        let listing = try ArchiveFallbackListing.bsdtar(tar)
        let ordinary = try ArchiveFallbackListing.bsdtar(
            Data("-rw-r--r--  0 0 0 12 Jan  1 12:00 notes link to self.txt\n".utf8))
        expect(ordinary.entries.first?.path == "notes link to self.txt", "Regular link-to filename accepted")
        expect(listing.entries.count == 3 && listing.totalBytes == 12, "Tar fields, spaces and sizes")
        try ArchiveRules.validate(listing, archiveBytes: 10)
        let xad = Data(#"""
        {"lsarFormatVersion":2,"lsarEncoding":"IBM852","lsarContents":[
        {"XADFileName":"żółć.txt","XADFileSize":12},{"XADFileName":"Folder","XADIsDirectory":true}]}
        """#.utf8)
        let parsed = try ArchiveFallbackListing.lsar(xad)
        expect(parsed.encoding == "IBM852" && parsed.listing.totalBytes == 12, "XAD JSON and encoding")
        try ArchiveRules.validate(parsed.listing, archiveBytes: 10)
        for path in ["../escape", "/absolute", "C:/drive", "folder\\file"] {
            let object: [String: Any] = ["lsarFormatVersion": 2, "lsarContents": [["XADFileName": path, "XADFileSize": 1]]]
            let json = try JSONSerialization.data(withJSONObject: object)
            refuses(.unsafePath(path)) {
                try ArchiveRules.validate(ArchiveFallbackListing.lsar(json).listing, archiveBytes: 100)
            }
        }
        refuses(.unsafePath("../escape")) {
            let data = Data("-rw-r--r--  0 0 0 1 Jan  1 12:00 ../escape\n".utf8)
            try ArchiveRules.validate(ArchiveFallbackListing.bsdtar(data), archiveBytes: 100)
        }
        refuses(.invalidListing) { _ = try ArchiveFallbackListing.bsdtar(Data("bad listing\n".utf8)) }
        refuses(.invalidListing) { _ = try ArchiveFallbackListing.lsar(Data("{}".utf8)) }
        let ancestor = Data(#"""
        {"lsarFormatVersion":2,"lsarContents":[
        {"XADFileName":"link","XADIsLink":true,"XADLinkDestination":"target"},
        {"XADFileName":"link/child","XADFileSize":1}]}
        """#.utf8)
        refuses(.symlinkAncestor("link/child")) {
            try ArchiveRules.validate(ArchiveFallbackListing.lsar(ancestor).listing, archiveBytes: 100)
        }
        let hardlink = Data(#"""
        {"lsarFormatVersion":2,"lsarContents":[{"XADFileName":"hard","XADIsHardLink":true,"XADFileSize":1}]}
        """#.utf8)
        refuses(.unsafePath("hard")) { _ = try ArchiveFallbackListing.lsar(hardlink) }
        let forks = Data(#"""
        {"lsarFormatVersion":2,"lsarContents":[{"XADFileName":"file","XADFileSize":1},
        {"XADFileName":"file","XADIsResourceFork":true,"XADFileSize":2},
        {"XADFileName":"fork-only","XADIsResourceFork":true,"XADFileSize":3}]}
        """#.utf8)
        let forkListing = try ArchiveFallbackListing.lsar(forks).listing
        expect(forkListing.entries.count == 2 && forkListing.totalBytes == 6, "Resource forks retain bytes and paths")
        try ArchiveRules.validate(forkListing, archiveBytes: 100)
        let unsafeFork = Data(#"""
        {"lsarFormatVersion":2,"lsarContents":[
        {"XADFileName":"../fork","XADIsResourceFork":true,"XADFileSize":1}]}
        """#.utf8)
        refuses(.unsafePath("../fork")) {
            try ArchiveRules.validate(ArchiveFallbackListing.lsar(unsafeFork).listing, archiveBytes: 100)
        }
        refuses(.invalidListing) {
            _ = try ArchiveFallbackListing.bsdtar(Data("hrw-r--r--  0 0 0 1 Jan  1 12:00 hard link to target\n".utf8))
        }
        refuses(.invalidListing) {
            let ambiguous = Data("lrwxrwxrwx  0 0 0 0 Jan  1 12:00 link -> /outside -> target\n".utf8)
            _ = try ArchiveFallbackListing.bsdtar(ambiguous)
        }
        refuses(.collision("a")) {
            let data = Data("-rw-r--r--  0 0 0 1 Jan  1 12:00 A\n-rw-r--r--  0 0 0 1 Jan  1 12:00 a\n".utf8)
            try ArchiveRules.validate(ArchiveFallbackListing.bsdtar(data), archiveBytes: 100)
        }
        refuses(.expansionLimit) {
            let stream = ArchiveFallbackListing.stream(URL(fileURLWithPath: "/huge.gz"), bytes: 5_000_000_001)
            try ArchiveRules.validate(stream, archiveBytes: 1)
        }
        print("PASS: bsdtar/lsar parsers, spaces, links, sizes, malformed data, unsafe paths, collisions and expansion limit")
    }

    @MainActor static func fakeXAD(_ root: URL) async throws {
        let tools = root.appending(path: "tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: false)
        let script = #"""
        #!/usr/bin/python3
        import json, os, pathlib, signal, sys, time
        args = sys.argv[1:]
        archive = pathlib.Path(args[-1])
        if pathlib.Path(sys.argv[0]).name == 'lsar':
            path = '../escape' if archive.stem == 'unsafe' else 'result.txt'
            print(json.dumps({'lsarFormatVersion': 2, 'lsarContents': [{'XADFileName': path, 'XADFileSize': 4}]}))
        else:
            assert '-nr' in args and '-D' in args and args[args.index('-k') + 1] == 'fork'
            (pathlib.Path(args[args.index('-o') + 1]) / 'result.txt').write_text('test')
            if archive.stem == 'slow' and (archive.parent / 'pause').exists():
                signal.signal(signal.SIGINT, signal.SIG_IGN)
                (archive.parent / 'child.pid').write_text(str(os.getpid()))
                time.sleep(30)
        """#
        for name in ["lsar", "unar"] {
            let tool = tools.appending(path: name)
            try script.write(to: tool, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        }
        var runner = ArchiveExtractionRunner()
        runner.fallbackTools.paths = [tools.path]
        let queue = ArchiveQueue(runner: runner)
        for name in ["safe.sit", "unsafe.sit"] {
            let archive = root.appending(path: name)
            try Data("fixture".utf8).write(to: archive)
            queue.enqueue(archive, mode: .inPlace)
        }
        while queue.jobs.contains(where: { [.queued, .preflighting, .extracting].contains($0.state) }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        expect(queue.jobs[0].state == .finished, "Fallback queue completes")
        expect(queue.jobs[0].effectiveMode == .keepArchive && queue.jobs[0].fallback != nil,
               "Fallback keeps archive in in-place mode")
        expect(queue.jobs[1].failure == .unsafePath("../escape"), "XAD validates before extraction")
        expect(ArchiveFiles.exists(root.appending(path: "safe.sit")), "Fallback source retained")
        let slow = root.appending(path: "slow.sit")
        let pause = root.appending(path: "pause")
        try Data("fixture".utf8).write(to: slow)
        try Data().write(to: pause)
        let identifier = queue.enqueue(slow, mode: .inPlace)
        for _ in 0..<500 {
            if ArchiveFiles.exists(root.appending(path: "child.pid")) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        expect(ArchiveFiles.exists(root.appending(path: "child.pid")), "Fallback process started")
        try await Task.sleep(for: .milliseconds(400))
        expect(queue.jobs.last?.bytesWritten == 4, "Fallback staging progress reaches job row")
        queue.cancel(identifier)
        for _ in 0..<500 {
            if queue.jobs.last?.state == .cancelled { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        expect(queue.jobs.last?.state == .cancelled && ArchiveFiles.exists(slow), "Fallback cancellation preserves source")
        expect(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .allSatisfy { !$0.hasPrefix(".notchcast-extract-") }, "Cancelled fallback staging and journals cleaned")
        try FileManager.default.removeItem(at: pause)
        queue.retry(identifier)
        for _ in 0..<500 {
            if queue.jobs.last?.state == .finished { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        expect(queue.jobs.last?.state == .finished, "Cancelled fallback retries through same queue")
        runner.fallbackTools.paths = []
        for name in ["missing.sit", "missing.zst"] {
            let archive = root.appending(path: name)
            try Data("fixture".utf8).write(to: archive)
            do {
                _ = try await runner.extract(archive)
                fatalError("Missing tool accepted")
            } catch {
                let command = name.hasSuffix("zst") ? "brew install zstd" : "brew install unar"
                expect(error as? ArchiveFailure == .fallbackToolMissing(command), "Specific install command")
            }
        }
        print("PASS: real queue hook, XAD keep-only, cancellation/retry, unsafe listing and brew install failures")
    }

    @MainActor static func realTools(_ root: URL) async throws {
        let tools = ArchiveFallbackTools()
        guard (try? tools.require("unar")) != nil, (try? tools.require("lsar")) != nil,
              (try? tools.require("zstd")) != nil else {
            print("NOT VERIFIED: install unar and zstd to run real-tool fixtures")
            return
        }
        let script = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "notchcast/test-archives-fallback.py")
        let generated = try await ArchiveProcess.run(tool: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [script.path, "generate", root.path], captureOutput: true)
        print(String(data: generated.output, encoding: .utf8) ?? "Invalid fixture output")
        expect(generated.status == 0, "Generate real fixtures")
        var outputs: [String: String] = [:]
        let runner = ArchiveExtractionRunner()
        let polish = root.appending(path: "mac-polish.zip")
        expect(!ArchiveZIPEncoding.inspect(try Data(contentsOf: polish)).requiresUnar, "ditto UTF-8 stays hatchzip")
        outputs["mac-polish.zip"] = try await runner.extract(polish).path
        print("PASS: ditto Polish ZIP routed through hatchzip")
        for name in ["sample.tar.xz", "sample.tar.bz2", "plain.txt.gz", "plain.txt.xz", "plain.txt.bz2",
                     "plain.txt.zst", "sample.tar.zst", "sample.iso", "windows.zip", "windows-1250.zip",
                     "empty.txt.gz", "empty.txt.xz", "empty.txt.bz2"] {
            let archive = root.appending(path: name)
            if name == "windows.zip" {
                expect(ArchiveZIPEncoding.inspect(try Data(contentsOf: archive)).requiresUnar, "CP852 central directory")
            }
            let output = try await runner.extract(archive, mode: .inPlace)
            outputs[name] = output.path
            expect(ArchiveFiles.exists(archive), "Real fallback keeps \(name)")
        }
        var nativeOnly = runner
        nativeOnly.fallbackTools.paths = []
        outputs["without-homebrew.tar.xz"] = try await nativeOnly.extract(root.appending(path: "sample.tar.xz")).path
        try JSONEncoder().encode(outputs).write(to: root.appending(path: "outputs.json"))
        let verified = try await ArchiveProcess.run(tool: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [script.path, "verify", root.path], captureOutput: true)
        print(String(data: verified.output, encoding: .utf8) ?? "Invalid comparison output")
        expect(verified.status == 0, "Diff real tools against sources")
        for name in ["unsafe.tar.xz", "absolute.tar.bz2", "collision.tar.xz", "ancestor.tar.xz",
                     "unsafe-windows.zip", "unsafe.tar.zst"] {
            do {
                _ = try await runner.extract(root.appending(path: name))
                fatalError("Accepted unsafe \(name)")
            } catch {
                switch error as? ArchiveFailure {
                case .unsafePath, .collision, .symlinkAncestor: break
                default: fatalError("Expected safety rejection for \(name), got \(error)")
                }
            }
        }
        expect(!ArchiveFiles.exists(root.appending(path: "escaped.txt")), "No fallback path escape")
        expect(!ArchiveFiles.exists(root.appending(path: "żółć.txt")), "No XAD path escape")
        expect(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .allSatisfy { !$0.hasPrefix(".notchcast-extract-") }, "Fallback staging cleaned")
        print("PASS: real bsdtar, zstd→bsdtar and unar reject unsafe paths before extraction; staging cleaned")
    }
}
