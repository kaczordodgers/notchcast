import Foundation

nonisolated enum MediaArguments {
    enum Format: Sendable { case video, audio }

    static func download(source: String, destination: URL, format: Format,
                         aria2Path: String? = nil, cookies: String? = nil) -> [String] {
        var arguments = common(destination: destination, cookies: cookies)
        arguments += ["--no-quiet", "--progress", "--progress-template",
                      "download:MEDIA_PROGRESS %(progress.downloaded_bytes)s %(progress.total_bytes)s "
                        + "%(progress.total_bytes_estimate)s %(progress.speed)s %(progress.eta)s",
                      "--print", "after_move:MEDIA_FILE %(filepath)j"]
        switch format {
        case .video:
            arguments += ["--format-sort", "vcodec:h264,res,acodec:aac", "--merge-output-format", "mp4",
                          "--remux-video", "mp4"]
        case .audio:
            arguments += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        }
        if let aria2Path {
            arguments += ["--downloader", aria2Path, "--downloader-args",
                          "aria2c:-x 16 -s 16 -k 1M --file-allocation=none"]
        }
        return arguments + ["--", source]
    }

    static func captions(source: String, destination: URL, automatic: Bool,
                         language: String, cookies: String? = nil) -> [String] {
        common(destination: destination, cookies: cookies)
            + ["--skip-download", automatic ? "--write-auto-subs" : "--write-subs",
               "--sub-langs", language, "--sub-format", "vtt/srt", "--", source]
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
