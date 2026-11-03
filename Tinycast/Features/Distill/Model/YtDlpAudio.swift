import Foundation

nonisolated enum YtDlpAudio {
    struct Media: Decodable, Equatable, Sendable {
        let title: String
        let channel: String?

        private enum CodingKeys: String, CodingKey { case title, fulltitle, id, channel, uploader, type = "_type" }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard try values.decodeIfPresent(String.self, forKey: .type) != "playlist" else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            title = try values.decodeIfPresent(String.self, forKey: .title)
                ?? values.decodeIfPresent(String.self, forKey: .fulltitle)
                ?? values.decode(String.self, forKey: .id)
            channel = try values.decodeIfPresent(String.self, forKey: .channel)
                ?? values.decodeIfPresent(String.self, forKey: .uploader)
        }
    }

    static let format = "bestaudio[ext=m4a]/bestaudio/best"

    static func metadataArguments(link: String) -> [String] {
        ["--ignore-config", "--no-playlist", "--skip-download", "--dump-single-json", "--", link]
    }

    static func audioArguments(link: String, folder: URL) -> [String] {
        ["--ignore-config", "--no-playlist", "--no-mtime", "--no-progress", "-f", format,
         "-o", folder.appending(path: "audio.%(ext)s").path, "--", link]
    }

    static func isMedia(_ url: URL) -> Bool {
        guard let rawHost = url.host?.lowercased() else { return false }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let hosts = ["youtube.com", "m.youtube.com", "youtu.be", "vimeo.com", "twitch.tv", "tiktok.com",
                     "dailymotion.com", "soundcloud.com", "podcasts.apple.com", "facebook.com",
                     "rumble.com", "bitchute.com", "loom.com", "wistia.com", "instagram.com"]
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
