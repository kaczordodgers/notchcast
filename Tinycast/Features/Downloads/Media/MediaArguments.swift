import Foundation

nonisolated enum MediaArguments {
    enum Format: Sendable { case video, audio }

    static func download(source: String, destination: URL, format: Format,
                         aria2Path: String? = nil, cookies: String? = nil,
                         restart: Bool = false, networkArguments: [String] = []) -> [String] {
        var arguments = common(destination: destination, cookies: cookies)
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

    static func probe(source: String, cookies: String?, format: Format) -> [String] {
        var arguments = ["--ignore-config", "--no-playlist", "--print", "%(filesize,filesize_approx)s"]
        arguments += selection(format)
        if let cookies, !cookies.isEmpty { arguments += ["--cookies-from-browser", cookies] }
        return arguments + ["--", source]
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
                         language: String? = nil, cookies: String? = nil) -> [String] {
        common(destination: destination, cookies: cookies)
            + ["--skip-download", automatic ? "--write-auto-subs" : "--write-subs",
               "--sub-langs", language ?? (automatic ? ".*-orig" : "all,-live_chat"),
               "--sub-format", "vtt/srt", "--", source]
    }

    static func originalLanguage(source: String, cookies: String?) -> [String] {
        var arguments = ["--ignore-config", "--no-playlist", "--skip-download", "--print", "%(language)s"]
        if let cookies, !cookies.isEmpty { arguments += ["--cookies-from-browser", cookies] }
        return arguments + ["--", source]
    }

    static func retryNatively(stderr: String, source: String, usedAria2: Bool) -> Bool {
        guard usedAria2, let host = URL(string: source)?.host?.lowercased(),
              host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") else { return false }
        return stderr.contains("403")
    }

    private static func common(destination: URL, cookies: String?) -> [String] {
        var arguments = ["--ignore-config", "--no-playlist", "--newline", "--no-colors", "--no-simulate",
                         "--paths", destination.path, "-o", "%(title)s [%(id)s].%(ext)s"]
        if let cookies, !cookies.isEmpty { arguments += ["--cookies-from-browser", cookies] }
        return arguments
    }
}
