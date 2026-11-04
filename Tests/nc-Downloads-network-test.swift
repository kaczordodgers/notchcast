// notchcast-sources: Tinycast/Features/Downloads/Media/*.swift Tinycast/Features/NetMerge/Model/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift Tinycast/Platform/NotificationToken.swift
import Foundation

@main
struct MediaNetworkTest {
    static func main() async throws {
        let wifi = NetMergePolicy.Interface(bsdName: "en0", kind: .wifi, hasIPv4: true)
        let phone = NetMergePolicy.Interface(bsdName: "en7", kind: .iPhoneUSB, hasIPv4: true)
        for (json, interfaces, enabled, expected) in [
            (#"{"filesize":200000000}"#, [wifi, phone], true, false),
            (#"{"filesize":200000001}"#, [wifi, phone], true, true),
            (#"{"filesize_approx":300000000}"#, [wifi], true, false),
            (#"{"filesize":300000000}"#, [wifi, phone], false, false),
            (#"{}"#, [wifi, phone], true, false)
        ] {
            let decision = NetMergePolicy.evaluate(interfaces: interfaces, kind: .download,
                sizeBytes: MediaNetwork.expectedSize(json), enabled: enabled)
            assert(decision.usesIPhone == expected)
            let args = MediaArguments.download(source: "https://example.com", destination: URL(filePath: "/tmp"),
                format: .video, aria2Path: "/fake/aria2c", networkArguments: decision.aria2Arguments)
            assert(args.contains(where: { $0.contains("--multiple-interface=en0,en7") }) == expected)
        }
        let combined = #"{"requested_formats":[{"filesize":150000000},{"filesize_approx":60000000}]}"#
        assert(MediaNetwork.expectedSize(combined) == 210000000)
        assert(MediaNetwork.expectedSize(#"{"requested_formats":[{"filesize":300000000},{}]}"#) == nil)
        for (enabled, interfaces, size, probes, merged) in [
            (false, [wifi, phone], 300000000, 0, false),
            (true, [wifi], 300000000, 0, false),
            (true, [wifi, phone], 300000000, 1, true),
            (true, [wifi, phone], 200000000, 1, false)
        ] {
            try await run(enabled: enabled, interfaces: interfaces, size: size, probes: probes, merged: merged)
        }
        print("Media network: small, big, missing iPhone, disabled and unknown sizes passed")
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
            --simulate) probe=true;;
          esac
          shift
        done
        if [ "$probe" = true ]; then
          echo probe >> "$dest/probes"
          echo '{"filesize":\(size)}'
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
        let runner = MediaDownloadRunner(format: .video, networkDecision: {
            NetMergePolicy.evaluate(interfaces: interfaces, kind: .download, sizeBytes: .max, enabled: enabled)
        })
        let job = DownloadJob(id: UUID().uuidString, kind: "video", source: "https://example.com/video",
                              title: "Video", state: .waiting, created: Date(), options: [:])
        _ = try await runner.run(job, context: DownloadRunContext(destination: root, tools: lookup))
        let log = (try? String(contentsOf: root.appending(path: "probes"), encoding: .utf8)) ?? ""
        precondition(log.split(separator: "\n").count == probes)
        let arguments = try String(contentsOf: root.appending(path: "arguments"), encoding: .utf8)
        precondition(arguments.contains("--multiple-interface=en0,en7") == merged)
    }
}
