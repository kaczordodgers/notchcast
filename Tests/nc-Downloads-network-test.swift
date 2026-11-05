// notchcast-sources: Tinycast/Features/Downloads/Media/*.swift Tinycast/Features/NetMerge/Model/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Distill/Model/*.swift Tinycast/Features/Distill/Service/DistillRunner.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DistillTranscriber.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DownloadRunContext+Distill.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationAudioChunks.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationModel.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationWire.swift
import Foundation

@main
struct MediaNetworkTest {
    static func main() async throws {
        let wifi = NetMergePolicy.Interface(bsdName: "en0", kind: .wifi, hasIPv4: true)
        let phone = NetMergePolicy.Interface(bsdName: "en7", kind: .iPhoneUSB, hasIPv4: true)
        for (output, interfaces, enabled, expected) in [
            ("200000000", [wifi, phone], true, false),
            ("200000001", [wifi, phone], true, true),
            ("300000000", [wifi], true, false),
            ("300000000", [wifi, phone], false, false),
            ("NA", [wifi, phone], true, false)
        ] {
            let decision = NetMergePolicy.evaluate(interfaces: interfaces, kind: .download,
                sizeBytes: MediaNetwork.expectedSize(output), enabled: enabled)
            assert(decision.usesIPhone == expected)
            let args = MediaArguments.download(source: "https://example.com", destination: URL(filePath: "/tmp"),
                format: .video, aria2Path: "/fake/aria2c", networkArguments: decision.aria2Arguments)
            assert(args.contains(where: { $0.contains("--multiple-interface=en0,en7") }) == expected)
        }
        assert(MediaNetwork.expectedSize("123456789") == 123456789)
        assert(MediaNetwork.expectedSize("[info] x\n300000000\n\n") == 300000000)
        for output in ["NA", "", "-5", "0", "9223372036854775808"] {
            assert(MediaNetwork.expectedSize(output) == nil)
        }
        for format in [MediaArguments.Format.video, .audio] {
            let probe = MediaArguments.probe(source: "file:///tmp/media.mp4", cookies: "firefox", format: format)
            let printIndex = probe.firstIndex(of: "--print")!
            assert(probe[printIndex + 1] == "%(filesize,filesize_approx)s")
            assert(!probe.contains("--dump-single-json") && !probe.contains("--simulate"))
            assert(!probe.contains("--no-quiet") && !probe.contains("--progress"))
            assert(probe.contains("firefox") && probe.suffix(2) == ["--", "file:///tmp/media.mp4"])
        }
        for (enabled, interfaces, size, probes, merged) in [
            (false, [wifi, phone], 300000000, 0, false),
            (true, [wifi], 300000000, 0, false),
            (true, [wifi, phone], 300000000, 1, true),
            (true, [wifi, phone], 200000000, 1, false)
        ] {
            try await run(enabled: enabled, interfaces: interfaces, size: size, probes: probes, merged: merged)
        }
        print("Media network: small, big, missing iPhone, disabled and unknown sizes passed")
        try await transcripts()
    }

    private static func transcripts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appending(path: "yt-dlp")
        let script = """
        #!/bin/sh
        dest=''
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --print) echo en; exit 0;;
            --paths) shift; dest="$1";;
          esac
          shift
        done
        printf 'WEBVTT\\n\\n00:00:00.000 --> 00:00:01.000\\n' > "$dest/same.en.vtt"
        /usr/bin/yes caption | /usr/bin/head -c 1000000 >> "$dest/same.en.vtt"
        """
        try script.write(to: tool, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        for round in 0..<12 {
            let folder = root.appending(path: "round-\(round)")
            let context = DownloadRunContext(destination: folder, tools: DownloadToolLookup(directories: [root]))
            let outputs = try await withThrowingTaskGroup(of: URL.self) { group in
                for _ in 0..<12 {
                    group.addTask {
                        let job = DownloadJob(id: UUID().uuidString, kind: "transcript", source: "fixture",
                            title: "Same", state: .waiting, created: Date(), options: [:])
                        return try await TranscriptDownloadRunner().run(job, context: context)!
                    }
                }
                var urls = [URL]()
                for try await url in group { urls.append(url) }
                return urls
            }
            precondition(Set(outputs).count == 12, "Concurrent transcripts overwrote each other")
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            precondition(files.count == 12)
        }
        print("PASS: concurrent transcript jobs preserve every output")
    }

    private static func run(enabled: Bool, interfaces: [NetMergePolicy.Interface],
                            size: Int, probes: Int, merged: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appending(path: "yt-dlp")
        let script = """
        #!/bin/sh
        dest=''
        probe=false
        args="$*"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --paths) shift; dest="$1";;
            --print) shift; [ "$1" != '%(filesize,filesize_approx)s' ] || probe=true;;
          esac
          shift
        done
        if [ "$probe" = true ]; then
          echo probe >> "\(root.path)/probes"
          echo '[info] selected formats'
          echo '\(size)'
        else
          echo "$args" > "$dest/arguments"
          touch "$dest/movie.mp4"
          printf 'MEDIA_FILE "%s/movie.mp4"\\n' "$dest"
        fi
        """
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        for name in ["ffmpeg", "aria2c"] {
            try FileManager.default.createSymbolicLink(at: root.appending(path: name), withDestinationURL: tool)
        }
        let lookup = DownloadToolLookup(directories: [root, URL(filePath: "/usr/bin"), URL(filePath: "/bin")])
        let runner = MediaDownloadRunner(format: .video, networkInterfaces: { enabled ? interfaces : [] })
        let job = DownloadJob(id: UUID().uuidString, kind: "video", source: "https://example.com/video",
                              title: "Video", state: .waiting, created: Date(), options: [:])
        _ = try await runner.run(job, context: DownloadRunContext(destination: root, tools: lookup))
        let log = (try? String(contentsOf: root.appending(path: "probes"), encoding: .utf8)) ?? ""
        precondition(log.split(separator: "\n").count == probes)
        let arguments = try String(contentsOf: root.appending(path: "arguments"), encoding: .utf8)
        precondition(arguments.contains("--multiple-interface=en0,en7") == merged)
    }
}
