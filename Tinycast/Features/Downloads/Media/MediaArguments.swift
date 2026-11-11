import Foundation

nonisolated enum MediaArguments {
    enum Format: Sendable {
        case video, audio

        var kind: String { self == .video ? "video" : "audio" }
    }

    static let rateLimitPause: Duration = .seconds(5)

    static func download(source: String, destination: URL, format: Format,
                         aria2Path: String? = nil, restart: Bool = false,
                         networkArguments: [String] = []) -> [String] {
        var arguments = common(destination: destination)
        if restart { arguments += ["--no-continue"] }
        arguments += ["--no-quiet", "--progress", "--progress-template",
                      "download:MEDIA_PROGRESS %(progress.downloaded_bytes)s %(progress.total_bytes)s "
                        + "%(progress.total_bytes_estimate)s %(progress.speed)s %(progress.eta)s",
                      "--print", "after_move:MEDIA_FILE %(filepath)j"]
        arguments += selection(format)
        if let aria2Path {
            arguments += ["--downloader", aria2Path, "--downloader-args",
                          (["aria2c:-x 16 -s 16 -k 1M --file-allocation=none"] + networkArguments).joined(separator: " ")]
        }
        return arguments + ["--", source]
    }

    static func probe(source: String, format: Format) -> [String] {
        base + ["--print", "%(filesize,filesize_approx)s"] + selection(format) + ["--", source]
    }

    private static func selection(_ format: Format) -> [String] {
        switch format {
        case .video:
            ["--format-sort", "vcodec:h264,res,acodec:aac", "--merge-output-format", "mp4", "--remux-video", "mp4"]
        case .audio:
            ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        }
    }

    static func captions(source: String, destination: URL, automatic: Bool,
                         language: String? = nil) -> [String] {
        // yt-dlp full-matches each code, so a regional track like pt-BR needs its full code.
        let tracks = language.map { full in
            let base = full.split(separator: "-").first.map(String.init) ?? full
            let regional = full == base ? [] : [full]
            return (automatic ? ["\(base)-orig", base] + regional : regional + [base]).joined(separator: ",")
        } ?? (automatic ? ".*-orig" : "all,-live_chat")
        return common(destination: destination)
            + ["--skip-download", automatic ? "--write-auto-subs" : "--write-subs", "--sub-langs", tracks,
               "--sleep-subtitles", "3", "--sub-format", "vtt/srt", "--", source]
    }

    static func isRateLimited(_ stderr: String) -> Bool { stderr.contains("HTTP Error 429") }

    // yt-dlp reports a rate-limited subtitle fetch on stderr yet still exits 0.
    static func retryCaptions(stderr: String, wroteCaptions: Bool) -> Bool {
        !wroteCaptions && isRateLimited(stderr)
    }

    static func originalLanguage(source: String) -> [String] {
        base + ["--skip-download", "--print", "%(language)s", "--", source]
    }

    static func retryNatively(stderr: String, source: String, usedAria2: Bool) -> Bool {
        usedAria2 && WebRules.isYouTubeHost(URL(string: source)?.host) && stderr.contains("403")
    }

    /// Every yt-dlp call reads no user config and takes one video, never a playlist.
    private static let base = ["--ignore-config", "--no-playlist"]

    private static func common(destination: URL) -> [String] {
        base + ["--newline", "--no-colors", "--no-simulate",
                "--paths", destination.path, "-o", "%(title)s [%(id)s].%(ext)s"]
    }
}
