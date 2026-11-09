// SPDX-License-Identifier: GPL-3.0-or-later

import Compression
import Foundation
import ImageIO

/// Firefox-family browsers publish a missing or tiny cover; their saved session leads to a sharp one.
enum BrowserCoverRules {
    /// The island draws a cover up to 320 pixels across; anything smaller blurs once stretched.
    static let minimumCoverPixels = 300
    static let maximumSessionBytes = 16 * 1_024 * 1_024
    /// The saved file is LZ4, a few times smaller than what it decodes to.
    static let maximumSessionFileBytes = 32 * 1_024 * 1_024
    static let maximumArtworkBytes = 4 * 1_024 * 1_024
    static let rememberedCovers = 8
    /// Firefox saves the session up to fifteen seconds after a change, so a new track may lag.
    static let attemptDelays: [Duration] = [.zero, .seconds(2), .seconds(5), .seconds(10), .seconds(18), .seconds(30)]
    static let failureCooldown: TimeInterval = 60

    /// Where each browser keeps its profiles, under Application Support.
    static let profileFolders: [String: String] = [
        "org.mozilla.firefox": "Firefox/Profiles",
        "org.mozilla.firefoxdeveloperedition": "Firefox/Profiles",
        "org.mozilla.nightly": "Firefox/Profiles",
        "app.zen-browser.zen": "zen/Profiles",
        "io.gitlab.librewolf-community": "librewolf/Profiles",
        "net.waterfox.waterfox": "Waterfox/Profiles",
        "one.ablaze.floorp": "Floorp/Profiles",
    ]

    /// The recovery file updates while the browser runs; the other is written on quit.
    static let sessionFiles = ["sessionstore-backups/recovery.jsonlz4", "sessionstore.jsonlz4"]

    struct SessionTab: Equatable, Sendable {
        let title: String
        let url: URL
    }

    /// Whether the player's own cover is missing or too small to show sharp.
    static func needsCover(_ artwork: Data?) -> Bool {
        guard let artwork,
              let source = CGImageSourceCreateWithData(artwork as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return true }
        return min(width, height) < minimumCoverPixels
    }

    /// Nil unless a Firefox-family browser plays it without a sharp cover; the artist splits namesakes.
    static func lookupKey(for track: NowPlaying) -> String? {
        guard let bundle = track.bundleID, profileFolders[bundle] != nil,
              !track.title.trimmingCharacters(in: .whitespaces).isEmpty, needsCover(track.artwork) else { return nil }
        return [bundle, track.artist, track.title].joined(separator: "\n")
    }

    /// `mozLz40\0`, the decoded size as a little-endian UInt32, then one raw LZ4 block.
    static func decodeMozLZ4(_ data: Data) -> Data? {
        guard data.count > 12, data.prefix(8).elementsEqual("mozLz40\0".utf8) else { return nil }
        let size = data.dropFirst(8).prefix(4).reversed().reduce(0) { $0 << 8 | Int($1) }
        guard size > 0, size <= maximumSessionBytes else { return nil }
        var output = Data(count: size)
        let written = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { out in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          input.bindMemory(to: UInt8.self).baseAddress! + 12,
                                          input.count - 12, nil, COMPRESSION_LZ4_RAW)
            }
        }
        return written == size ? output : nil
    }

    /// The page each tab shows now: `entries` is its back history and `index` counts from 1.
    static func openTabs(inSession json: Data) -> [SessionTab] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let windows = root["windows"] as? [[String: Any]] else { return [] }
        return windows.flatMap { window in
            (window["tabs"] as? [[String: Any]] ?? []).compactMap { tab -> SessionTab? in
                guard let entries = tab["entries"] as? [[String: Any]], !entries.isEmpty else { return nil }
                let current = min(max((tab["index"] as? Int ?? entries.count) - 1, 0), entries.count - 1)
                guard let title = entries[current]["title"] as? String,
                      let address = entries[current]["url"] as? String,
                      let url = URL(string: address) else { return nil }
                return SessionTab(title: title, url: url)
            }
        }
    }

    private static let youTubeHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com",
                                                    "music.youtube.com", "youtu.be"]

    /// Every other tab is dropped as soon as the session is read, so nothing else stays in memory.
    static func youTubeTabs(_ tabs: [SessionTab]) -> [SessionTab] {
        tabs.filter { youTubeHosts.contains($0.url.host?.lowercased() ?? "") }
    }

    /// YouTube Music plays on while its tab shows another page; a fresh session must still show it.
    static func asksAppleMusic(tabs: [SessionTab], savedAt: Date, lookupStarted: Date) -> Bool {
        savedAt >= lookupStarted && tabs.contains { $0.url.host?.lowercased() == "music.youtube.com" }
    }

    /// Cover addresses for the tab that names the track, best first.
    static func artworkURLs(forTrack title: String?, artist: String? = nil, in tabs: [SessionTab]) -> [URL] {
        guard let title else { return [] }
        let track = normalizedTabTitle(title)
        guard track.count >= 2 else { return [] }
        let credit = artist.map(normalizedTabTitle)
        guard let tab = tabs.first(where: {
            !thumbnailURLs(forPage: $0.url).isEmpty && names(normalizedTabTitle($0.title), track, artist: credit)
        }) else { return [] }
        return thumbnailURLs(forPage: tab.url)
    }

    private static let siteSuffixes = [" - youtube music", " | youtube music", " - youtube", " | youtube"]

    /// The track alone or "track • artist": "Stay" never takes "Stay - Someone Else", nor "Home" "Homeland".
    private static func names(_ tabTitle: String, _ track: String, artist: String?) -> Bool {
        let suffix = siteSuffixes.first { tabTitle.hasSuffix($0) }
        let page = String(tabTitle.dropLast(suffix?.count ?? 0))
        if page == track { return true }
        guard let artist, !artist.isEmpty else { return false }
        return page == track + " • " + artist
    }

    /// The browser collapses runs of spaces in a saved title and may prefix an unread count "(3)".
    private static func normalizedTabTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: #"^\s*\(\d+\+?\)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Without an artist a title alone would match covers of other songs, so there is no search.
    static func appleMusicSearchURL(title: String, artist: String?, country: String?) -> URL? {
        guard let artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty,
              !title.trimmingCharacters(in: .whitespaces).isEmpty,
              var url = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        url.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: country.flatMap { $0.count == 2 ? $0 : nil } ?? "US"),
        ]
        return url.url
    }

    /// The 600-pixel art of the result whose title and artist both match, only from Apple's image servers.
    static func appleMusicArtworkURL(inSearch json: Data, title: String, artist: String?) -> URL? {
        guard let artist,
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return nil }
        let wantedTitle = folded(title)
        let wantedArtist = folded(artist)
        guard let match = results.first(where: { result in
            guard let name = result["trackName"] as? String,
                  let credit = result["artistName"] as? String else { return false }
            let artists = folded(credit)
            return folded(name) == wantedTitle
                && (holdsName(wantedArtist, in: artists) || holdsName(artists, in: wantedArtist))
        }), let small = match["artworkUrl100"] as? String, small.hasSuffix("/100x100bb.jpg"),
              let cover = URL(string: String(small.dropLast("100x100bb.jpg".count)) + "600x600bb.jpg"),
              cover.scheme?.lowercased() == "https",
              cover.host?.lowercased().hasSuffix(".mzstatic.com") == true else { return nil }
        return cover
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whole words only: "keshi" is named by "keshi & Jay", "Mia" is not named by "Jeremias".
    private static func holdsName(_ name: String, in credit: String) -> Bool {
        guard !name.isEmpty else { return false }
        let pattern = #"(?<![\p{L}\p{M}\p{N}])"# + NSRegularExpression.escapedPattern(for: name)
            + #"(?![\p{L}\p{M}\p{N}])"#
        return credit.range(of: pattern, options: .regularExpression) != nil
    }

    static func centreSquare(width: Int, height: Int) -> CGRect {
        let side = max(0, min(width, height))
        return CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
    }

    /// A 16:9 thumbnail shrunk to the island keeps too few rows, so the cover is its centre square.
    static func squareCover(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let square = image.cropping(to: centreSquare(width: image.width, height: image.height))
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, square,
                                   [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// `maxresdefault` is missing for some older videos; neither adds the bands `hqdefault` has.
    static func thumbnailURLs(forPage url: URL) -> [URL] {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else { return [] }
        let path = url.pathComponents.filter { $0 != "/" }
        let id: String?
        if host == "youtu.be" {
            id = path.first
        } else if youTubeHosts.contains(host) {
            if path.first == "watch" {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value
            } else if path.count >= 2, ["shorts", "live", "embed"].contains(path[0]) {
                id = path[1]
            } else {
                id = nil
            }
        } else {
            id = nil
        }
        guard let id, id.count == 11,
              id.unicodeScalars.allSatisfy({
                  $0.isASCII && CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0)
              })
        else { return [] }
        return ["maxresdefault", "mqdefault"].compactMap { URL(string: "https://i.ytimg.com/vi/\(id)/\($0).jpg") }
    }
}
