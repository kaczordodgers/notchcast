import Foundation

struct DownloadTool: Sendable, Hashable {
    let name: String
    let installCommand: String
    var versionArguments: [String] = ["--version"]

    static let ytDlp = DownloadTool(name: "yt-dlp", installCommand: "brew install yt-dlp")
    static let ffmpeg = DownloadTool(name: "ffmpeg", installCommand: "brew install ffmpeg", versionArguments: ["-version"])
    static let aria2c = DownloadTool(name: "aria2c", installCommand: "brew install aria2")

    var missingDetail: String {
        String(localized: "\(name) is not installed. Install it with: \(installCommand)")
    }
}
