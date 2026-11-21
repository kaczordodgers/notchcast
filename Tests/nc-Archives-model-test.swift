// notchcast-sources: Tinycast/Features/Notchcast/Archives/Model/*.swift

import Foundation

func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { fatalError(message()) }
}

func routing() {
    let cases: [(String, ArchiveEngine, String)] = [
        ("Game.zip", .hatchzip, "Game"), ("set.7z", .hatchzip, "set"), ("Movie.rar", .hatchzip, "Movie"),
        ("Movie.part1.rar", .hatchzip, "Movie"), ("Movie.part12.rar", .hatchzip, "Movie"), ("Movie.r00", .hatchzip, "Movie"),
        ("big.7z.001", .hatchzip, "big"), ("big.7z.002", .hatchzip, "big"), ("logs.tar.gz.001", .hatchzip, "logs"),
        ("src.tar", .hatchzip, "src"), ("src.tar.gz", .hatchzip, "src"), ("src.TGZ", .hatchzip, "src"),
        ("src.tar.bz2", .hatchzip, "src"), ("src.tbz2", .hatchzip, "src"), ("src.tar.xz", .hatchzip, "src"),
        ("src.tar.zst", .bsdtar, "src"), ("src.tzst", .bsdtar, "src"), ("disk.iso", .bsdtar, "disk"),
        ("setup.cab", .bsdtar, "setup"), ("Installer.pkg", .bsdtar, "Installer"), ("a.xar", .bsdtar, "a"),
        ("a.cpio", .bsdtar, "a"), ("notes.txt.gz", .gzip, "notes.txt"), ("dump.bz2", .bzip2, "dump"),
        ("dump.xz", .xz, "dump"), ("dump.zst", .zstd, "dump"), ("Old.sit", .unar, "Old"), ("Old.sitx", .unar, "Old"),
        ("a.lzh", .unar, "a"), ("a.lha", .unar, "a"), ("a.arj", .unar, "a"), ("a.Z", .unar, "a"),
        ("a.arc", .unar, "a"), ("a.zoo", .unar, "a"), ("Mixed.Case.Name.ZIP", .hatchzip, "Mixed.Case.Name"),
    ]
    for (name, engine, stem) in cases {
        let route = ArchiveRoute(fileName: name)
        check(route == ArchiveRoute(engine: engine, stem: stem),
              "\(name) routes to \(engine) as \(stem): \(String(describing: route))")
    }
    for name in ["notes.txt", "photo.jpg", ".zip", "zip", "a.dmg", "a.docx", ".001", "r00", "part1.rar.txt"] {
        check(ArchiveRoute(fileName: name) == nil, "\(name) is no archive")
    }
    check(!ArchiveRoute.defaultExtensions.contains("pkg") && !ArchiveRoute.defaultExtensions.contains("iso"),
          "installers and disk images keep their own default apps")
    for ext in ArchiveRoute.defaultExtensions {
        check(ArchiveRoute(fileName: "x.\(ext)") != nil || ext == "001", "default extension \(ext) has a route")
    }
    check(ArchiveRoute(fileName: "x.7z.001") != nil, "a first volume has a route")
}

func arguments() {
    let archive = URL(filePath: "/Volumes/Data/Inbox/My Game.zip")
    let staging = URL(filePath: "/Volumes/Data/Inbox/.notchcast-extract-1")
    let tool = URL(filePath: "/opt/homebrew/bin/hatchzip")
    let extract = { (engine: ArchiveEngine, inPlace: Bool) in
        ArchiveCommandLine.extract(
            engine, tool: tool, archive: archive, staging: staging, stem: "My Game", inPlace: inPlace, outputBlocks: 77)
    }
    check(extract(.hatchzip, false) == ["extract", archive.path, "-o", staging.path, "-q", "--keep-archive"],
          "keeping is the default and never needs a confirmation")
    check(extract(.hatchzip, true) == ["extract", archive.path, "-o", staging.path, "-q", "-y"],
          "in place answers HatchZip's prompt, since no terminal is attached")
    check(extract(.bsdtar, false) == ["-xf", archive.path, "-C", staging.path], "bsdtar extracts into staging")
    check(extract(.unar, false) == ["-o", staging.path, "-D", "-q", archive.path], "unar adds no folder of its own")
    check(extract(.gzip, false) == ["-c", #"ulimit -f "$3" && exec "$0" -dc "$1" > "$2""#, tool.path, archive.path,
                                    staging.appending(path: "My Game").path, "77"],
          "a stream goes through sh as positional arguments, never spliced into the script, under a size cap")
    check(ArchiveSafety.outputBlocks(archiveSize: 10_000_000) == 10_000_000_000 / 1024, "the cap is 1000x the archive")
    check(ArchiveSafety.outputBlocks(archiveSize: 10) == 5_000_000_000 / 1024, "and never under 5 GB")
    check(ArchiveSafety.outputBlocks(archiveSize: .max) > 0, "a huge size does not wrap the cap")
    check(ArchiveCommandLine.list(.hatchzip, archive: archive) == ["list", archive.path], "hatchzip lists")
    check(ArchiveCommandLine.list(.bsdtar, archive: archive) == ["-tvf", archive.path], "bsdtar lists verbosely")
    check(ArchiveCommandLine.list(.unar, archive: archive) == ["-j", archive.path], "lsar lists as JSON")
    check(ArchiveCommandLine.list(.zstd, archive: archive) == nil, "a single stream has nothing to list")
    check(ArchiveCommandLine.tools(.unar) == (.lsar, .unar), "unar lists with lsar")
    check(ArchiveCommandLine.check(archive: archive, staging: staging) == ["check", archive.path, "-o", staging.path],
          "check plans in place")
    check(ArchiveCommandLine.restore(archive: archive, staging: staging) == ["restore", archive.path, "-o", staging.path],
          "restore names the same output folder")
}

func listings() throws {
    // Real `hatchzip list` output, 0.1.10, piped (no colour).
    let hatchzip = """
              Size  Name
               6 B  one/a.txt
               2 B  one/sub/b c.txt
                    one/sub/
                    one/link (symlink)
                    one/hard (link to one/a.txt)
           12.5 KB  top.txt
        6 entries, 9 B uncompressed, 321 B zip archive
        """
    let listing = ArchiveListing.hatchzip(hatchzip)
    check(!listing.isMalformed, "one line per entry and a matching count read as sound")
    check(listing.entries[4].hardLinkTarget == "one/a.txt", "a hard link's target is read")
    let oneEntry = { (extraLine: String) in
        ArchiveListing.hatchzip(
            "      Size  Name\n       1 B  a\n\(extraLine)\n1 entry, 1 B uncompressed, 7 B zip archive\n")
    }
    check(oneEntry("/../../../evil").isMalformed, "a name with a line break cannot hide the rest of its path")
    check(oneEntry("       1 B  b").isMalformed, "more lines than the totals line counts is refused")
    check(oneEntry("1 entry, /../x uncompressed, y").isMalformed, "a second totals line is refused")
    check(ArchiveListing.hatchzip("").isMalformed, "no totals line is refused")
    check(listing.entries.map(\.path) == ["one/a.txt", "one/sub/b c.txt", "one/sub", "one/link", "one/hard", "top.txt"],
          "hatchzip paths: \(listing.entries.map(\.path))")
    check(listing.entries[2].isDirectory && listing.entries[3].isLink && !listing.entries[4].isLink, "kinds read")
    check(listing.entries[5].size == 12_500, "sizes are powers of 1000")
    check(listing.expandedSize == 9 && listing.archiveSize == 321, "the footer gives both totals")
    check(ArchiveListing.size("1.5 GB") == 1_500_000_000 && ArchiveListing.size("7 B") == 7, "size units")

    let bsdtar = """
        drwxr-xr-x  0 me     staff       0 Jan  1 12:00 one/
        -rw-r--r--  0 me     staff    1234 Jan  1  2024 one/a b.txt
        lrwxr-xr-x  0 me     staff       0 Jan  1 12:00 one/link -> /etc
        hrw-r--r--  0 me     staff       0 Jan  1 12:00 one/hard link to one/a b.txt
        """
    let tar = ArchiveListing.bsdtar(bsdtar)
    check(tar.entries.map(\.path) == ["one", "one/a b.txt", "one/link", "one/hard"], "bsdtar paths: \(tar.entries.map(\.path))")
    check(tar.entries[0].isDirectory && tar.entries[2].isLink && tar.expandedSize == 1234, "bsdtar kinds and sizes")
    check(tar.entries[3].hardLinkTarget == "one/a b.txt" && tar.entries[2].hardLinkTarget == nil, "bsdtar hard link target")

    let lsar = Data("""
        {"lsarFormatVersion":2,"lsarContents":[{"XADFileName":"Old/Read Me","XADFileSize":42,"XADIsDirectory":0},
        {"XADFileName":"Old","XADIsDirectory":1},{"XADFileName":"Old/alias","XADIsLink":true}]}
        """.utf8)
    let unar = try ArchiveListing.lsar(lsar)
    check(unar.entries.map(\.path) == ["Old/Read Me", "Old", "Old/alias"] && unar.expandedSize == 42, "lsar entries")
    check(unar.entries[1].isDirectory && unar.entries[2].isLink, "lsar flags as numbers or booleans")
}

func safety() {
    func refusal(_ paths: [String], links: [String] = [], expanded: Int64? = nil, archive: Int64 = 1000) -> ArchiveRefusal? {
        let entries = paths.map { ArchiveEntry(path: $0) } + links.map { ArchiveEntry(path: $0, isLink: true) }
        return ArchiveSafety.refusal(for: ArchiveListing(entries: entries, expandedSize: expanded), archiveSize: archive)
    }
    check(refusal(["a/b.txt", "a/c.txt", "d"]) == nil, "a plain archive passes")
    check(refusal(["../evil"]) == .parentPath("../evil"), "../evil is refused")
    check(refusal(["a/../../evil"]) == .parentPath("a/../../evil"), "a nested escape is refused")
    check(refusal(["a\\..\\evil"]) == .parentPath("a\\..\\evil"), "a Windows-separated escape is refused")
    check(refusal(["/etc/passwd"]) == .absolutePath("/etc/passwd"), "an absolute path is refused")
    check(refusal(["C:\\Windows\\x"]) == .driveLetter("C:\\Windows\\x"), "a drive letter is refused")
    check(refusal(["Read.me", "read.ME"]) == .caseCollision("Read.me", "read.ME"), "case-folded twins are refused")
    check(refusal(["Docs/a", "docs/b"]) == .caseCollision("Docs", "docs"), "folders that fold together are refused")
    check(refusal(["a", "a/"]) == nil, "a folder listed twice is fine")
    check(refusal(["x/payload"], links: ["x"]) == .underLink("x/payload"), "nothing is written through a link")
    check(refusal(["./x/payload"], links: ["x"]) == .underLink("./x/payload"), "a dot does not hide the link")
    check(refusal(["x"], links: ["y"]) == nil, "a link beside files is fine")
    check(refusal(["bomb"], expanded: 6_000_000_000, archive: 1_000_000) == .expansion(6_000_000_000),
          "over 5 GB and over 1000x is a bomb")
    check(refusal(["big"], expanded: 6_000_000_000, archive: 100_000_000) == nil, "a large archive that is 60x is fine")
    check(refusal(["small"], expanded: 4_000_000_000, archive: 1) == nil, "under 5 GB is fine at any ratio")
    let split = ArchiveListing(entries: [ArchiveEntry(path: "v")], expandedSize: 6_000_000_000, archiveSize: 100_000_000)
    check(ArchiveSafety.refusal(for: split, archiveSize: 1_000) == nil, "a split set counts every volume")
    check(ArchiveFailure.unsafe(.parentPath("../evil")).message.contains("../evil"), "the refusal names the path")
    func linked(_ target: String) -> ArchiveRefusal? {
        ArchiveSafety.refusal(
            for: ArchiveListing(entries: [ArchiveEntry(path: "a"), ArchiveEntry(path: "hard", hardLinkTarget: target)]),
            archiveSize: 1000)
    }
    check(linked("a") == nil, "a hard link to a file in the archive is fine")
    check(linked("/etc/passwd") == .absolutePath("/etc/passwd"), "a hard link to an absolute path is refused")
    check(linked("x/../../secret") == .parentPath("x/../../secret"), "a hard link out of the folder is refused")
    var malformed = ArchiveListing(entries: [ArchiveEntry(path: "a")])
    malformed.isMalformed = true
    check(ArchiveSafety.refusal(for: malformed, archiveSize: 1000) == .unreadableListing, "an unsound listing is refused")
}

func placement() {
    let existing: Set<String> = ["Game", "Game 2", "notes.txt", "notes 2.txt", "Game.zip", ".env"]
    let taken = { existing.contains($0) }
    check(ArchivePlacement.plan(items: ["a", "b"], stem: "Game", taken: taken) == .folder(name: "Game 3"),
          "several items get a fresh folder named after the archive")
    check(ArchivePlacement.plan(items: ["a", "b"], stem: "Other", taken: taken) == .folder(name: "Other"), "free name kept")
    check(ArchivePlacement.plan(items: ["notes.txt"], stem: "Game", taken: taken) == .item("notes.txt", name: "notes 3.txt"),
          "one item goes beside the archive, never over a file")
    check(ArchivePlacement.plan(items: ["Photos"], stem: "Game", taken: taken) == .item("Photos", name: "Photos"),
          "one folder keeps its own name")
    check(ArchivePlacement.plan(items: [".env"], stem: "x", taken: taken) == .item(".env", name: ".env 2"),
          "a dot file has no extension to keep")
    check(ArchivePlacement.plan(items: [], stem: "x", taken: taken) == .empty, "an empty archive places nothing")
    check(ArchivePlacement.freeName("Game", keepsExtension: false, taken: taken) == "Game 3", "folders count on")
}

func failures() {
    let missing = ArchiveFailure.missingTool(.hatchzip).message
    check(missing == "hatchzip is not installed. Install it with: brew install xevrion/tap/hatchzip", missing)
    let result = { (status: Int32) in ArchiveProcessResult(status: status, errors: "error: it broke\n") }
    check(ArchiveFailure.hatchzip(result(0)) == nil, "0 is success")
    check(ArchiveFailure.hatchzip(result(3)) == .noSpace("it broke"), "3 is no space")
    check(ArchiveFailure.hatchzip(result(4)) == .damaged("it broke"), "4 is damage")
    check(ArchiveFailure.hatchzip(result(5)) == .password, "5 is a password")
    check(ArchiveFailure.hatchzip(result(1)) == .failed("it broke"), "anything else is a failure with its words")
    check(ArchiveFailure.tool(result(2)) == .failed("it broke"), "fallback tools fail with their words")
    let elsewhere = ArchiveProcessResult(
        status: 1, errors: "error: this archive is already partially extracted to /x. Complete or restore that extraction first")
    check(ArchiveFailure.hatchzip(elsewhere) == .startedElsewhere("/x"), "progress HatchZip holds elsewhere is named plainly")
}

func passwords() {
    let steps = (0...3).map { ArchivePassword.next(asked: $0) }
    check(steps == [.ask(wrong: false), .ask(wrong: true), .ask(wrong: true), .giveUp], "three tries: \(steps)")
    check(ArchivePassword.environment("pw", engine: .hatchzip) == ["HATCHZIP_PASSWORD": "pw"], "HatchZip gets the variable")
    check(ArchivePassword.environment(nil, engine: .hatchzip).isEmpty, "no password, no variable")
    for engine in [ArchiveEngine.bsdtar, .unar, .gzip, .bzip2, .xz, .zstd] {
        check(ArchivePassword.environment("pw", engine: engine).isEmpty, "\(engine) never gets it")
    }
    for name in ["a.zip", "A.ZIP"] { check(ArchivePassword.allowsInPlace(fileName: name), "\(name) may go in place") }
    for name in ["a.7z", "a.rar", "a.part1.rar", "a.7z.001", "a.tar.gz"] {
        check(!ArchivePassword.allowsInPlace(fileName: name), "\(name) is kept")
    }
}

func journal() {
    let job = ArchiveJob(id: UUID(), archive: URL(filePath: "/tmp/In Box/Game.zip"), inPlace: true)
    check(job.staging.deletingLastPathComponent().path == "/tmp/In Box", "staging sits beside the archive")
    check(job.staging.lastPathComponent.hasPrefix(".notchcast-extract-"), "staging is hidden")
    check(ArchiveJob.decode(ArchiveJob.encode([job])) == [job], "the journal round-trips")
    check(ArchiveJob.decode(Data("garbage".utf8)).isEmpty, "a damaged journal resumes nothing")
    var stopped = job
    stopped.stopped = ArchiveFingerprint(size: 7, stoppedAt: Date(timeIntervalSinceReferenceDate: 1.25))
    check(ArchiveJob.decode(ArchiveJob.encode([stopped])) == [stopped], "a stopped entry round-trips")
    let older = #"[{"id":"\#(job.id)","archive":"file:///tmp/a.7z","staging":"file:///tmp/.s/","inPlace":false}]"#
    let oldStopped = older.replacingOccurrences(
        of: #""inPlace":false"#, with: #""inPlace":false,"stopped":{"size":7,"modified":1.25}"#)
    check(ArchiveJob.decode(Data(oldStopped.utf8)).first?.stopped == ArchiveFingerprint(size: 7),
          "a stopped entry with the old fingerprint still decodes")
    check(ArchiveJob.decode(Data(older.utf8)).first?.stopped == nil, "a journal from before `stopped` still decodes")
}

func zipNames() {
    func entry(_ name: [UInt8], utf8Flag: Bool) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 46)
        header[0...3] = [0x50, 0x4B, 0x01, 0x02]
        header[9] = utf8Flag ? 0x08 : 0x00
        header[28] = UInt8(name.count)
        return header + name
    }
    let cp437 = entry([0x82, 0x61], utf8Flag: false)
    let flagged = entry(Array("é".utf8), utf8Flag: true)
    let unflaggedUTF8 = entry(Array("é".utf8), utf8Flag: false)
    check(ZIPNameEncoding.hasLegacyNames(directory: Data(cp437)), "a code-page name is legacy")
    check(!ZIPNameEncoding.hasLegacyNames(directory: Data(flagged + unflaggedUTF8)), "UTF-8 names are not")
    check(ZIPNameEncoding.hasLegacyNames(directory: Data(flagged + cp437)), "one legacy name is enough")
    var end = [UInt8](repeating: 0, count: 22)
    end[0...3] = [0x50, 0x4B, 0x05, 0x06]
    end[12] = 48
    end[16] = 7
    let found = ZIPNameEncoding.directory(tail: Data([1, 2, 3] + end))
    check(found?.offset == 7 && found?.size == 48, "the end record gives the directory")
    end[16...19] = [0xFF, 0xFF, 0xFF, 0xFF]
    check(ZIPNameEncoding.directory(tail: Data(end)) == nil, "ZIP64 is left to HatchZip")
}

/// A property list keeps only the last of two equal keys, which once dropped the torrent types.
func plistKeys() throws {
    let plist = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Tinycast/Info.plist")
    let keys = try String(contentsOf: plist, encoding: .utf8).split(separator: "\n")
        .filter { $0.hasPrefix("\t<key>") }.map(String.init)
    check(keys.count > 10, "the top-level keys are read: \(keys.count)")
    let repeated = Set(keys.filter { key in keys.count { $0 == key } > 1 })
    check(repeated.isEmpty, "Info.plist names a top-level key twice, so the first one is lost: \(repeated)")
}

/// A fake disk for planning: kinds by path, every folder writable unless listed.
func plan(
    _ format: ArchiveFormat, _ paths: [String], kinds: [String: ArchiveItemKind] = [:], readOnly: Set<String> = []
) -> Result<CompressionPlan, ArchiveFailure> {
    let urls = paths.map { $0.hasPrefix("/") ? URL(filePath: $0) : URL(string: $0)! }
    return Result { () throws(ArchiveFailure) in
        try ArchiveCompression.plan(
            format: format, selection: urls, kind: { kinds[$0.path] ?? .file },
            isWritable: { !readOnly.contains($0.path) })
    }
}

func compressionNames() throws {
    let two = try plan(.zip, ["/x/Trip/a.txt", "/x/Trip/b.txt"]).get()
    check(two.stem == "Trip" && two.folder.path == "/x/Trip" && two.single == nil && two.label == "Trip.zip",
          "several items are named after their folder and land in it: \(two)")
    for format in ArchiveFormat.allCases {
        check(try plan(format, ["/x/Trip/a.txt", "/x/Trip/b.txt"]).get().label == "Trip.\(format.rawValue)",
              "\(format) names several items after their folder")
    }
    let notes = try plan(.zip, ["/x/notes.txt"]).get()
    check(notes.label == "notes.txt.zip" && notes.single == .file, "one file keeps its whole name: \(notes)")
    let photos = try plan(.sevenZip, ["file:///x/Trip/Photos/"], kinds: ["/x/Trip/Photos": .folder]).get()
    check(photos.label == "Photos.7z" && photos.folder.path == "/x/Trip" && photos.single == .folder,
          "Finder's folder URL ends in a slash and still names the folder: \(photos)")
    let doubled = try plan(.zip, ["file:///x/Trip/a.txt", "/x/Trip/a.txt", "/x/Trip/./a.txt", "https://example.com/b.txt"])
        .get()
    check(doubled.inputs.map(\.path) == ["/x/Trip/a.txt"], "duplicates count once, web links are dropped: \(doubled)")

    var existing: Set<String> = ["Trip.tar.zst", "notes.txt.zip"]
    let taken = { existing.contains($0) }
    check(ArchiveCompression.outputName(stem: "Trip", format: .tarZstd, taken: taken) == "Trip 2.tar.zst",
          "the number goes before the whole extension")
    existing.insert("Trip 2.tar.zst")
    check(ArchiveCompression.outputName(stem: "Trip", format: .tarZstd, taken: taken) == "Trip 3.tar.zst", "and counts on")
    check(ArchiveCompression.outputName(stem: "notes.txt", format: .zip, taken: taken) == "notes.txt 2.zip",
          "a file's own extension stays in the stem")
    check(ArchiveCompression.outputName(stem: "Trip", format: .zip, taken: taken) == "Trip.zip", "a free name is kept")

    let ascii = String(repeating: "a", count: 250)
    let cutASCII = ArchiveCompression.cut(ascii, format: .zip)
    check(cutASCII.utf8.count == 247 && (cutASCII + " 999.zip").utf8.count == 255, "\(cutASCII.utf8.count) bytes")
    let accents = String(repeating: "é", count: 125)
    let cutAccents = ArchiveCompression.cut(accents, format: .tarZstd)
    check(accents.hasPrefix(cutAccents) && cutAccents.utf8.count == 242 && cutAccents.count == 121,
          "two-byte characters are kept whole: \(cutAccents.utf8.count) bytes")
    let families = String(repeating: "👨‍👩‍👧", count: 20)
    let cutFamilies = ArchiveCompression.cut(families, format: .sevenZip)
    check(families.hasPrefix(cutFamilies) && cutFamilies.utf8.count <= 247 && cutFamilies.count == 13,
          "a joined emoji is never split: \(cutFamilies.count) characters")
    check(ArchiveCompression.cut("Trip", format: .zip) == "Trip", "a short name is untouched")
    check(try plan(.zip, ["/x/" + ascii]).get().stem == cutASCII, "the plan cuts the name")
}

func compressionRefusals() throws {
    let cases: [(Result<CompressionPlan, ArchiveFailure>, ArchiveFailure)] = [
        (plan(.zip, []), .nothingSelected),
        (plan(.zip, ["https://example.com/a.zip"]), .nothingSelected),
        (plan(.zip, ["/x/A/a.txt", "/x/B/b.txt"]), .severalFolders),
        (plan(.zip, ["file:///"], kinds: ["/": .folder]), .notCompressible("/")),
        (plan(.zip, ["/x/a.txt", "/x/pipe"], kinds: ["/x/pipe": .other]), .notCompressible("pipe")),
        (plan(.zip, ["/x/a.txt"], readOnly: ["/x"]), .notWritable("x")),
    ]
    for (result, expected) in cases {
        guard case .failure(let failure) = result else { return check(false, "\(expected) refuses: \(result)") }
        check(failure == expected, "\(expected), got \(failure)")
    }
    check(try plan(.zip, ["/x/link"], kinds: ["/x/link": .link]).get().zipsClones, "a lone link is zipped as a clone")
    check(ArchiveFailure.severalFolders.message == "Select items from one folder.", ArchiveFailure.severalFolders.message)
    check(ArchiveFailure.compressionFailed("").message == "Compression failed.", "a silent tool still says something")
    check(ArchiveFailure.missingTool(.sevenZip).message == "7zz is not installed. Install it with: brew install sevenzip",
          ArchiveFailure.missingTool(.sevenZip).message)
}

func compressionArguments() throws {
    let staged = URL(filePath: "/x/.tmp/Output.zip")
    let tools = [URL(filePath: "/bin/tool"), URL(filePath: "/opt/home brew/bin/zstd")]
    func arguments(_ plan: CompressionPlan, clones: URL? = nil) -> [String] {
        ArchiveCommandLine.compress(plan, tools: tools, staged: staged, clones: clones)
    }
    let file = try plan(.zip, ["/x/notes.txt"]).get()
    check(arguments(file) == ["-c", "-k", "--sequesterRsrc", "/x/notes.txt", staged.path], "\(arguments(file))")
    let folder = try plan(.zip, ["/x/Photos"], kinds: ["/x/Photos": .folder]).get()
    check(arguments(folder) == ["-c", "-k", "--sequesterRsrc", "--keepParent", "/x/Photos", staged.path],
          "a lone folder keeps its own name inside the ZIP: \(arguments(folder))")
    let names = ["/x/Trip/-dash.txt", "/x/Trip/@at.txt", "/x/Trip/sub"]
    let several = try plan(.zip, names).get()
    check(several.zipsClones, "several items go into a ZIP as clones")
    let clones = URL(filePath: "/x/.tmp/Items")
    check(arguments(several, clones: clones) == ["-c", "-k", "--sequesterRsrc", clones.path, staged.path],
          "ditto zips the clones' folder without it, so the items sit at the top: \(arguments(several, clones: clones))")
    let seven = try plan(.sevenZip, names).get()
    check(arguments(seven) == ["a", "-t7z", "-mx=9", "-snl", "-spd", "-bd", "-y", "--", staged.path] + names,
          "7z takes absolute paths after --, so - and @ names stay names: \(arguments(seven))")
    let tar = try plan(.tarZstd, names).get()
    check(arguments(tar) == [
        "--use-compress-program", "\"/opt/home brew/bin/zstd\"", "-cf", staged.path, "-C", "/x/Trip",
        "./-dash.txt", "./@at.txt", "./sub",
    ], "bsdtar runs the located zstd and reads ./ names from the folder: \(arguments(tar))")
    let odd = ArchiveCommandLine.compress(
        tar, tools: [tools[0], URL(filePath: "/opt/a\"b\\c/zstd")], staged: staged, clones: nil)
    check(odd[1] == #""/opt/a\"b\\c/zstd""#, "a quote or backslash in zstd's path is escaped: \(odd[1])")
}

@main
enum ArchivesModelTest {
    static func main() throws {
        routing()
        arguments()
        try listings()
        safety()
        placement()
        failures()
        passwords()
        journal()
        zipNames()
        try compressionNames()
        try compressionRefusals()
        try compressionArguments()
        try plistKeys()
        print("nc-Archives-model-test: ok")
    }
}
