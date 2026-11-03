// notchcast-sources: Tinycast/Features/Downloads/Media/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import Foundation

@main struct DownloadsMediaTest {
    static func main() async throws {
        let destination = URL(filePath: "/tmp/media")
        let source = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        let native = MediaArguments.download(source: source, destination: destination, format: .video)
        precondition(!native.contains("--downloader") && !native.contains("--cookies-from-browser"))
        precondition(native.contains("mp4") && native.suffix(2) == ["--", source])
        let audio = MediaArguments.download(source: source, destination: destination, format: .audio,
                                            aria2Path: "/opt/homebrew/bin/aria2c", cookies: "firefox:profile")
        precondition(audio.contains("mp3") && audio.contains("firefox:profile"))
        precondition(audio.contains("aria2c:-x 16 -s 16 -k 1M --file-allocation=none"))
        precondition(MediaArguments.retryNatively(stderr: "HTTP Error 403: Forbidden", source: source, usedAria2: true))
        precondition(!MediaArguments.retryNatively(stderr: "403", source: source, usedAria2: false))
        precondition(!MediaArguments.retryNatively(stderr: "HTTP Error 403", source: "https://example.com", usedAria2: true))
        let restarted = MediaArguments.download(source: source, destination: destination, format: .video, restart: true)
        precondition(restarted.contains("--no-continue"))
        let manual = MediaArguments.captions(source: source, destination: destination, automatic: false)
        let automatic = MediaArguments.captions(source: source, destination: destination, automatic: true)
        precondition(manual.contains("all,-live_chat") && !manual.contains("en"))
        precondition(automatic.contains(".*-orig") && !automatic.contains("en"))
        precondition(manual.contains("--write-subs") && !manual.contains("--write-auto-subs"))
        precondition(automatic.contains("--write-auto-subs") && !automatic.contains("--write-subs"))
        let progress = MediaOutput.progress("MEDIA_PROGRESS 4200 NA 10000 18000000.0 105")!
        precondition(progress.fraction == 0.42 && progress.eta == 105)
        let completed = MediaOutput.progress("MEDIA_PROGRESS 629172 629172 NA 2021060.1325613454 NA")!
        precondition(completed.fraction == 1 && completed.eta == nil)
        precondition(completed.bytesPerSecond == 2021060.1325613454)
        precondition(MediaOutput.progress("MEDIA_PROGRESS nan inf NA -1 NA")?.received == nil)
        precondition(MediaOutput.progress("[download] Destination: movie.mp4") == nil)
        let output = MediaOutput.outputPath("MEDIA_FILE \"/tmp/media/movie.mp4\"", destination: destination)
        precondition(output?.lastPathComponent == "movie.mp4")
        precondition(MediaOutput.outputPath("MEDIA_FILE \"/tmp/media/../escape.mp4\"", destination: destination) == nil)
        let captions = "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nhello <00:00:00.500><c>world</c>"
            + "\n\n00:00:01.000 --> 00:00:02.000\nhello world again"
            + "\n\n00:00:02.000 --> 00:00:03.000\nworld again &amp; goodbye"
        precondition(CaptionText.plainText(captions, automatic: true) == "hello world again & goodbye")
        precondition(CaptionText.plainText(captions) == "hello world hello world again world again & goodbye")
        let srt = "1\n00:00:00,000 --> 00:00:01,000\nHello\n\n2\n00:00:01,000 --> 00:00:02,000\nthere"
        precondition(CaptionText.plainText(srt) == "Hello there")
        precondition(CaptionText.plainText("WEBVTT\n\nNOTE no captions") == "")
        try await runners()
        print("downloads-media-test: passed")
    }

    private static func runners() async throws {
        let root = URL(filePath: ProcessInfo.processInfo.environment["DOWNLOAD_MEDIA_TEST_ROOT"] ?? NSTemporaryDirectory())
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appending(path: "yt-dlp")
        let script = """
        #!/bin/sh
        dest=''
        mode=media
        language=''
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --paths) shift; dest="$1";;
            --write-subs) mode=manual;;
            --write-auto-subs) mode=auto;;
            --sub-langs) shift; language="$1";;
            --print) shift; [ "$1" != '%(language)s' ] || mode=metadata;;
          esac
          shift
        done
        if [ "$mode" = metadata ]; then
          printf 'pl\\n'
        elif [ "$mode" = manual ]; then
          [ "$language" = pl ] || exit 1
          printf 'WEBVTT\\n\\n00:00:00.000 --> 00:00:01.000\\nDzień dobry\\n' > "$dest/Movie [id].pl.vtt"
        elif [ "$mode" = auto ]; then
          exit 1
        elif [ "$mode" = media ]; then
          touch "$dest/movie.mp4"
          printf 'MEDIA_PROGRESS 50 100 NA 10 5\\n'
          printf 'MEDIA_FILE "%s/movie.mp4"\\n' "$dest"
        fi
        """
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "ffmpeg"), withDestinationURL: tool)
        let lookup = DownloadToolLookup(directories: [root, URL(filePath: "/usr/bin"), URL(filePath: "/bin")])
        let context = DownloadRunContext(destination: root, tools: lookup)
        let job = DownloadJob(id: UUID().uuidString, kind: "video", source: "https://example.com/video",
                              title: "Video", state: .waiting, created: Date(), options: [:])
        let output = try await MediaDownloadRunner(format: .video).run(job, context: context)
        precondition(output?.lastPathComponent == "movie.mp4")
        let transcript = try await TranscriptDownloadRunner().run(job, context: context)
        let text = try String(contentsOf: transcript!, encoding: .utf8)
        precondition(text == "Dzień dobry")
        precondition(transcript?.lastPathComponent == "Movie [id].txt")
        let second = try await TranscriptDownloadRunner().run(job, context: context)
        precondition(second?.lastPathComponent == "Movie [id] (2).txt")
    }
}
