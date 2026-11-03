import Foundation

@main struct DownloadsMediaTest {
    static func main() throws {
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
        precondition(CaptionText.plainText(captions) == "hello world again & goodbye")
        let srt = "1\n00:00:00,000 --> 00:00:01,000\nHello\n\n2\n00:00:01,000 --> 00:00:02,000\nthere"
        precondition(CaptionText.plainText(srt) == "Hello there")
        precondition(CaptionText.plainText("WEBVTT\n\nNOTE no captions") == "")
        print("downloads-media-test: passed")
    }
}
