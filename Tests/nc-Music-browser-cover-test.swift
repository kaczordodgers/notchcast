// notchcast-sources: Tinycast/Features/Music/Model/*.swift
// notchcast-sources: Tinycast/Features/Music/Service/*.swift
// notchcast-kit: core
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import AppKit
import ImageIO

@MainActor
final class Log {
    var reads = 0
    var fetched: [URL] = []
    var session: BrowserCoverSession?
    var replies: [String: Data] = [:]
    var held: URL?
    var gate: CheckedContinuation<Void, Never>?

    func read(_ bundleID: String) -> BrowserCoverSession? {
        reads += 1
        return session
    }

    func fetch(_ url: URL) async -> Data? {
        fetched.append(url)
        if url == held { await withCheckedContinuation { gate = $0 } }
        return replies[url.absoluteString]
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
final class FakeSource: NowPlayingSource {
    var track: NowPlaying?
    private var onChange: (@MainActor () -> Void)?
    func watch(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    func unwatch() { onChange = nil }
    func read() async throws -> NowPlaying? { track }
    func send(_ command: PlayerCommand) {}

    func play(_ track: NowPlaying?) {
        self.track = track
        onChange?()
    }
}

func jpeg(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

func pixels(_ data: Data?) -> (Int, Int)? {
    guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (width, height)
}

func track(_ title: String, artist: String = "Artist", bundleID: String = "app.zen-browser.zen",
           artwork: Data? = nil) -> NowPlaying {
    NowPlaying(title: title, artist: artist, album: "", app: "Zen", bundleID: bundleID, duration: 180, elapsed: 0,
               stamp: Date(timeIntervalSinceReferenceDate: 0), isPlaying: true, artwork: artwork, origin: .system)
}

func tab(_ title: String, _ address: String) -> BrowserCoverRules.SessionTab {
    BrowserCoverRules.SessionTab(title: title, url: URL(string: address)!)
}

@main
@MainActor
struct BrowserCoverTests {
    static func main() async {
        decoding()
        matching()
        appleSearch()
        await lifecycle()
        print("PASS: session decode, tab matching, Apple search, off reads nothing, stale replies dropped")
    }

    static func decoding() {
        let session = Data("""
            {"windows":[{"tabs":[
              {"index":2,"entries":[{"url":"https://www.youtube.com/watch?v=aaaaaaaaaaa","title":"Old video - YouTube"},
                {"url":"https://www.youtube.com/watch?v=1PxhTfmEyQ8&t=42","title":"(3) My favorite browser is (kind of) dead - YouTube"}]},
              {"index":1,"entries":[{"url":"https://www.google.com/search?q=browser","title":"My favorite browser is (kind of) dead - Google Search"}]},
              {"index":1,"entries":[{"url":"https://music.youtube.com/watch?v=8_fkyx42kL0&list=RDAMVM","title":"she likes spring, I prefer winter | YouTube Music"}]},
              {"index":1,"entries":[{"url":"https://www.youtube.com/watch?v=bbbbbbbbbbb","title":"Went back - YouTube"},
                {"url":"https://www.youtube.com/watch?v=ccccccccccc","title":"Forward page - YouTube"}]}
            ]}]}
            """.utf8)
        let literals = [UInt8](session)
        var block: [UInt8] = [0xF0]
        var remaining = literals.count - 15
        while remaining >= 255 { block.append(255); remaining -= 255 }
        block.append(UInt8(remaining))
        block += literals
        let size = UInt32(literals.count)
        let container = Data(Array("mozLz40\0".utf8) + (0..<4).map { UInt8(truncatingIfNeeded: size >> (8 * $0)) } + block)
        precondition(BrowserCoverRules.decodeMozLZ4(container) == session, "a session container decodes to its JSON")
        precondition(BrowserCoverRules.decodeMozLZ4(Data("mozLz40\0".utf8) + Data([0, 0, 0, 0, 0])) == nil
            && BrowserCoverRules.decodeMozLZ4(Data("not a session".utf8)) == nil
            && BrowserCoverRules.decodeMozLZ4(container.dropLast(4)) == nil, "empty, foreign or truncated reads as nothing")
        let repeating: [UInt8] = [0x44] + Array("abcd".utf8) + [4, 0, 0xC0] + Array("0123456789AB".utf8)
        let header = Array("mozLz40\0".utf8) + [24, 0, 0, 0]
        precondition(BrowserCoverRules.decodeMozLZ4(Data(header + repeating)) == Data("abcdabcdabcd0123456789AB".utf8))
        var reachesBack = repeating
        reachesBack[5] = 16
        precondition(BrowserCoverRules.decodeMozLZ4(Data(header + reachesBack)) == nil, "a match before the start is refused")
        let oversized = BrowserCoverRules.maximumSessionBytes + 1
        let extra = oversized - 1 - 12 - 4 - 15
        let flood: [UInt8] = [0x1F, 0x61, 1, 0] + [UInt8](repeating: 255, count: extra / 255) + [UInt8(extra % 255)]
            + [0xC0] + Array("0123456789AB".utf8)
        let floodHeader = Array("mozLz40\0".utf8) + (0..<4).map { UInt8(truncatingIfNeeded: oversized >> (8 * $0)) }
        precondition(BrowserCoverRules.decodeMozLZ4(Data(floodHeader + flood)) == nil, "the decoded cap holds")
        precondition(oversized == 16 * 1_024 * 1_024 + 1, "a session past 16 MiB never decodes, inside the memory budget")

        let tabs = BrowserCoverRules.openTabs(inSession: session)
        precondition(tabs.count == 4 && tabs[0].title.hasPrefix("(3) My favorite") && tabs[3].title == "Went back - YouTube",
                     "each tab reads as the page it shows now")
        precondition(BrowserCoverRules.openTabs(inSession: Data("{\"windows\":[{\"tabs\":".utf8)).isEmpty
            && BrowserCoverRules.openTabs(inSession: Data("[1,2]".utf8)).isEmpty, "malformed JSON reads as no tabs")
        precondition(BrowserCoverRules.artworkURLs(forTrack: "My favorite browser is (kind of) dead", in: tabs)
            .map(\.absoluteString) == ["https://i.ytimg.com/vi/1PxhTfmEyQ8/maxresdefault.jpg",
                                       "https://i.ytimg.com/vi/1PxhTfmEyQ8/mqdefault.jpg"],
                     "the playing tab gives its full thumbnail first, ahead of a search for the same title")
        precondition(BrowserCoverRules.artworkURLs(forTrack: "she likes spring, I prefer winter", in: tabs)
            .first?.absoluteString == "https://i.ytimg.com/vi/8_fkyx42kL0/maxresdefault.jpg"
            && BrowserCoverRules.artworkURLs(forTrack: "Midnight City", in: tabs).isEmpty)
        let folders = BrowserCoverRules.profileFolders
        precondition(folders["app.zen-browser.zen"] == "zen/Profiles" && folders["org.mozilla.firefox"] == "Firefox/Profiles"
            && ["com.apple.Music", "com.spotify.client", "com.google.Chrome", "com.apple.Safari"]
                .allSatisfy { folders[$0] == nil }
            && folders.values.allSatisfy { $0.hasSuffix("/Profiles") }, "only Firefox-family sessions are read")
    }

    static func matching() {
        let watching = { (title: String) in tab(title, "https://www.youtube.com/watch?v=1PxhTfmEyQ8") }
        precondition(BrowserCoverRules.artworkURLs(forTrack: "Home", in: [watching("Homeland trailer - YouTube"),
                                                                           watching("Coming Home live - YouTube")]).isEmpty
            && !BrowserCoverRules.artworkURLs(forTrack: "Home", in: [watching("(2) Home - YouTube")]).isEmpty
            && !BrowserCoverRules.artworkURLs(forTrack: "Home", artist: "Artist",
                                              in: [watching("Home • Artist - YouTube Music")]).isEmpty
            && BrowserCoverRules.artworkURLs(forTrack: "Home", artist: "Artist",
                                             in: [watching("Home • Someone Else - YouTube Music")]).isEmpty
            && BrowserCoverRules.artworkURLs(forTrack: "Stay", artist: "The Kid LAROI",
                                             in: [watching("Stay - Rihanna ft. Mikky Ekko - YouTube")]).isEmpty,
                     "a short title takes only the tab that names it whole")
        precondition(!BrowserCoverRules.artworkURLs(forTrack: "Home  Again ", in: [watching("Home Again - YouTube")]).isEmpty,
                     "doubled spaces still match the collapsed saved title")
        let search = tab("Search", "https://www.google.com/search?q=x")
        let musicHome = tab("keshi - YouTube Music", "https://music.youtube.com/channel/UC123")
        let began = Date(timeIntervalSinceReferenceDate: 1_000)
        precondition(BrowserCoverRules.youTubeTabs([search, musicHome, watching("Video - YouTube")]).count == 2
            && BrowserCoverRules.asksAppleMusic(tabs: [musicHome], savedAt: began + 3, lookupStarted: began)
            && !BrowserCoverRules.asksAppleMusic(tabs: [musicHome], savedAt: began - 3, lookupStarted: began)
            && !BrowserCoverRules.asksAppleMusic(tabs: [watching("Video - YouTube")], savedAt: began + 3, lookupStarted: began))
        let page = { (address: String) in BrowserCoverRules.thumbnailURLs(forPage: URL(string: address)!).first?.absoluteString }
        precondition(page("https://youtu.be/1PxhTfmEyQ8?si=x") == "https://i.ytimg.com/vi/1PxhTfmEyQ8/maxresdefault.jpg"
            && page("https://m.youtube.com/shorts/1PxhTfmEyQ8") != nil
            && page("https://www.youtube.com/live/1PxhTfmEyQ8") != nil
            && page("https://www.youtube.com/watch?v=short") == nil
            && page("https://www.youtube.com/watch?v=1PxhTfmEy/8") == nil
            && page("https://www.youtube.com/@channel") == nil
            && page("https://evil.example/watch?v=1PxhTfmEyQ8") == nil
            && page("file:///watch?v=1PxhTfmEyQ8") == nil, "only a well-formed YouTube video address yields a thumbnail")
        precondition(BrowserCoverRules.centreSquare(width: 1280, height: 720) == CGRect(x: 280, y: 0, width: 720, height: 720)
            && BrowserCoverRules.centreSquare(width: 300, height: 400) == CGRect(x: 0, y: 50, width: 300, height: 300))
        precondition(BrowserCoverRules.needsCover(nil) && BrowserCoverRules.needsCover(jpeg(width: 60, height: 60))
            && BrowserCoverRules.needsCover(Data("not an image".utf8))
            && !BrowserCoverRules.needsCover(jpeg(width: 720, height: 720)), "a 60-pixel cover is replaced, a sharp one stays")
        precondition(BrowserCoverRules.lookupKey(for: track("Song", artwork: jpeg(width: 60, height: 60))) != nil
            && BrowserCoverRules.lookupKey(for: track("Song", artwork: jpeg(width: 720, height: 720))) == nil
            && BrowserCoverRules.lookupKey(for: track("Song", bundleID: "com.spotify.client")) == nil
            && BrowserCoverRules.lookupKey(for: track(" ")) == nil
            && BrowserCoverRules.lookupKey(for: track("Song", artist: "A")) != BrowserCoverRules.lookupKey(for: track("Song")))
        let square = BrowserCoverRules.squareCover(jpeg(width: 1280, height: 720))
        precondition(pixels(square).map { $0 == (720, 720) } == true, "a thumbnail becomes its centre square")
    }

    static func appleSearch() {
        let search = BrowserCoverRules.appleMusicSearchURL(title: "less of you", artist: "keshi", country: "PH")
        let items = search.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        precondition(search?.host == "itunes.apple.com" && items.contains(URLQueryItem(name: "term", value: "keshi less of you"))
            && items.contains(URLQueryItem(name: "country", value: "PH"))
            && BrowserCoverRules.appleMusicSearchURL(title: "less of you", artist: nil, country: nil) == nil
            && BrowserCoverRules.appleMusicSearchURL(title: "less of you", artist: " ", country: nil) == nil
            && BrowserCoverRules.appleMusicSearchURL(title: "x", artist: "y", country: "bogus")
                .map { $0.absoluteString.contains("country=US") } == true, "no search on a title alone")
        let reply = Data("""
            {"resultCount":3,"results":[
              {"trackName":"Skeletons (Piano Version)","artistName":"thepianokid",
               "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/piano.jpg/100x100bb.jpg"},
              {"trackName":"less of you","artistName":"thepianokid",
               "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/cover.jpg/100x100bb.jpg"},
              {"trackName":"Less Of You","artistName":"keshi",
               "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/83/20UMGIM13994.rgb.jpg/100x100bb.jpg"}
            ]}
            """.utf8)
        precondition(BrowserCoverRules.appleMusicArtworkURL(inSearch: reply, title: "less of you", artist: "keshi")?
            .absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/83/20UMGIM13994.rgb.jpg/600x600bb.jpg")
        precondition(BrowserCoverRules.appleMusicArtworkURL(inSearch: reply, title: "skeletons", artist: "keshi") == nil
            && BrowserCoverRules.appleMusicArtworkURL(inSearch: reply, title: "less of you", artist: "Someone Else") == nil
            && BrowserCoverRules.appleMusicArtworkURL(inSearch: Data("{}".utf8), title: "a", artist: "b") == nil
            && BrowserCoverRules.appleMusicArtworkURL(inSearch: Data("not json".utf8), title: "a", artist: "b") == nil,
                     "a near miss never borrows an album's art")
        let namesake = Data("""
            {"results":[
              {"trackName":"Hello","artistName":"Jeremias","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/jeremias.jpg/100x100bb.jpg"},
              {"trackName":"Hello","artistName":"Adele","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/adele.jpg/100x100bb.jpg"},
              {"trackName":"Hello","artistName":"Mia & Jay","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/mia.jpg/100x100bb.jpg"}
            ]}
            """.utf8)
        precondition(BrowserCoverRules.appleMusicArtworkURL(inSearch: namesake, title: "Hello", artist: "Mia")?
            .absoluteString.contains("/mia.jpg/600x600bb.jpg") == true
            && BrowserCoverRules.appleMusicArtworkURL(inSearch: namesake, title: "Hello", artist: "A") == nil
            && BrowserCoverRules.appleMusicArtworkURL(inSearch: namesake, title: "Hello", artist: "Jay & Mia & Zoe") == nil,
                     "an artist matches whole names only")
        let elsewhere = Data(#"{"results":[{"trackName":"Less Of You","artistName":"keshi","artworkUrl100":"https://images.example/thumb/a.jpg/100x100bb.jpg"}]}"#.utf8)
        precondition(BrowserCoverRules.appleMusicArtworkURL(inSearch: elsewhere, title: "less of you", artist: "keshi") == nil,
                     "art loads only from Apple's image servers")
    }

    static func lifecycle() async {
        let suite = "browser-cover.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(!preferences.isOn(.musicSharpCovers), "sharp covers start off")
        let log = Log()
        let clock = Date(timeIntervalSinceReferenceDate: 10_000)
        let finder = BrowserCoverFinder(readSession: { await log.read($0) }, fetch: { url, _ in await log.fetch(url) },
                                        now: { clock }, sleep: { _ in await Task.yield() }, country: "PL")
        let apps = PlayerApps(isInstalled: { _ in false }, isRunning: { _ in false }, open: { _ in }, play: { _ in },
                              watchLaunches: { _ in [] }, quit: { _ in true })
        let model = MusicModel(defaults: defaults, apps: apps)
        let source = FakeSource()
        model.setSystemSource(source)
        model.setEnabled(true)
        let controller = NotchcastModuleController([.init(
            requires: [.island, .musicNowPlaying, .musicSharpCovers],
            module: MusicSharpCoversModule(model: model, finder: finder))], preferences: preferences)
        controller.run()

        let thumb = "https://i.ytimg.com/vi/1PxhTfmEyQ8/maxresdefault.jpg"
        log.session = BrowserCoverSession(savedAt: clock, tabs: [tab("Song - YouTube", "https://www.youtube.com/watch?v=1PxhTfmEyQ8")])
        log.replies[thumb] = jpeg(width: 1280, height: 720)
        let small = jpeg(width: 60, height: 60)
        source.play(track("Song", artwork: small))
        await waitUntil { model.nowPlaying?.title == "Song" }
        await settle()
        precondition(log.reads == 0 && log.fetched.isEmpty && model.nowPlaying?.artwork == small,
                     "with the switch off nothing is read or fetched")

        preferences.set(.musicSharpCovers, true)
        await waitUntil { pixels(model.nowPlaying?.artwork).map { $0 == (720, 720) } == true }
        precondition(log.reads == 1 && log.fetched.map(\.absoluteString) == [thumb] && model.nowPlaying?.title == "Song",
                     "the playing tab's thumbnail becomes the track's cover")

        let spotify = track("Song", bundleID: "com.spotify.client", artwork: small)
        source.play(spotify)
        await waitUntil { model.nowPlaying?.bundleID == "com.spotify.client" }
        await settle()
        precondition(model.nowPlaying?.artwork == small && log.reads == 1, "another player's artwork is untouched")

        source.play(track("Song", artwork: small))
        await waitUntil { model.nowPlaying?.bundleID == "app.zen-browser.zen" }
        precondition(pixels(model.nowPlaying?.artwork).map { $0 == (720, 720) } == true && log.reads == 1,
                     "a remembered cover returns without another lookup")

        let alphaThumb = "https://i.ytimg.com/vi/aaaaaaaaaaa/maxresdefault.jpg"
        log.session = BrowserCoverSession(savedAt: clock, tabs: [tab("Alpha - YouTube", "https://www.youtube.com/watch?v=aaaaaaaaaaa")])
        log.replies[alphaThumb] = jpeg(width: 1280, height: 720)
        log.held = URL(string: alphaThumb)
        source.play(track("Alpha"))
        await waitUntil { log.gate != nil }
        log.session = nil
        source.play(track("Beta"))
        await waitUntil { model.nowPlaying?.title == "Beta" }
        log.release()
        await settle()
        log.held = nil
        source.play(track("Alpha"))
        await waitUntil { model.nowPlaying?.title == "Alpha" }
        precondition(model.nowPlaying?.artwork == nil, "a reply for a replaced track never applies")
        source.play(spotify)
        await waitUntil { model.nowPlaying?.bundleID == "com.spotify.client" }
        await settle()

        let fetchedBefore = log.fetched.count
        log.session = BrowserCoverSession(savedAt: clock + 1, tabs: [tab("keshi - YouTube Music", "https://music.youtube.com/channel/UC1")])
        let art = "https://is1-ssl.mzstatic.com/image/thumb/a/x.jpg/600x600bb.jpg"
        let search = BrowserCoverRules.appleMusicSearchURL(title: "Less Of You", artist: "keshi", country: "PL")!
        let small100 = "https://is1-ssl.mzstatic.com/image/thumb/a/x.jpg/100x100bb.jpg"
        log.replies[search.absoluteString] = Data(
            #"{"results":[{"trackName":"Less Of You","artistName":"keshi","artworkUrl100":"\#(small100)"}]}"#.utf8)
        log.replies[art] = jpeg(width: 600, height: 600)
        source.play(track("Less Of You", artist: ""))
        await waitUntil { model.nowPlaying?.title == "Less Of You" }
        await settle()
        precondition(!log.fetched.dropFirst(fetchedBefore).contains { $0.host == "itunes.apple.com" },
                     "no artist means no Apple search")
        source.play(track("Less Of You", artist: "keshi"))
        await waitUntil { pixels(model.nowPlaying?.artwork).map { $0 == (600, 600) } == true }
        precondition(log.fetched.dropFirst(fetchedBefore).map(\.absoluteString) == [search.absoluteString, art],
                     "YouTube Music asks Apple once and loads its album art")

        let readsBefore = log.reads
        preferences.set(.musicSharpCovers, false)
        await waitUntil { model.nowPlaying?.artwork == nil }
        source.play(track("Gamma"))
        await waitUntil { model.nowPlaying?.title == "Gamma" }
        await settle()
        precondition(log.reads == readsBefore, "switching off stops lookups and restores the player's own cover")
    }

    static func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("timed out")
    }
}
