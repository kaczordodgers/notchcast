// notchcast-sources: Tinycast/Features/Music/Model/*.swift
// notchcast-sources: Tinycast/Features/Music/Service/*.swift Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-kit: core
// notchcast-sources: Tinycast/Platform/KeychainSecretStore.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import Foundation
import Network
import Synchronization
import ImageIO

final class Clock: Sendable {
    let date = Mutex(Date(timeIntervalSinceReferenceDate: 10_000))
    func advance(_ seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

@MainActor
final class Lookups {
    var reads = 0
    var session: BrowserCoverSession?
    var replies: [String: Data] = [:]
}

/// Answers each path with a fixed reply and records what reached it.
final class Server: Sendable {
    let listener: NWListener
    let requests = Mutex<[(path: String, accept: String?)]>([])

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [self] connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let lines = (String(bytes: data ?? Data(), encoding: .utf8) ?? "").components(separatedBy: "\r\n")
                let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let accept = lines.first { $0.lowercased().hasPrefix("accept:") }
                    .map { String($0.dropFirst("accept:".count)).trimmingCharacters(in: .whitespaces) }
                self.requests.withLock { $0.append((path, accept)) }
                connection.send(content: self.reply(path), contentContext: .finalMessage, isComplete: true,
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
    }

    func base() async -> String {
        while listener.port == nil { try? await Task.sleep(for: .milliseconds(10)) }
        return "http://127.0.0.1:\(listener.port!.rawValue)"
    }

    private func reply(_ path: String) -> Data {
        let huge = BrowserCoverRules.maximumArtworkBytes + 1
        let (head, body): (String, Data) = switch path {
        case "/cover": ("200 OK\r\nContent-Length: 5", Data("cover".utf8))
        case "/redirect": ("302 Found\r\nLocation: /cover\r\nContent-Length: 0", Data())
        case "/declared": ("200 OK\r\nContent-Length: \(huge)", Data(count: huge))
        case "/streamed": ("200 OK\r\nConnection: close", Data(count: huge))
        default: ("404 Not Found\r\nContent-Length: 0", Data())
        }
        return Data("HTTP/1.1 \(head)\r\n\r\n".utf8) + body
    }
}

func mozLZ4(_ json: String) -> Data {
    let literals = [UInt8](json.utf8)
    var block: [UInt8] = [0xF0]
    var remaining = literals.count - 15
    while remaining >= 255 { block.append(255); remaining -= 255 }
    block.append(UInt8(remaining))
    block += literals
    let size = UInt32(literals.count)
    return Data(Array("mozLz40\0".utf8) + (0..<4).map { UInt8(truncatingIfNeeded: size >> (8 * $0)) } + block)
}

func session(_ title: String, _ video: String) -> Data {
    mozLZ4(#"{"windows":[{"tabs":[{"index":1,"entries":[{"url":"https://www.youtube.com/watch?v=\#(video)","title":"\#(title) - YouTube"}]}]}]}"#)
}

func track(_ title: String) -> NowPlaying {
    NowPlaying(title: title, artist: "Artist", album: "", app: "Zen", bundleID: "app.zen-browser.zen", duration: 180,
               elapsed: 0, stamp: Date(timeIntervalSinceReferenceDate: 0), isPlaying: true, artwork: nil, origin: .system)
}

@main
@MainActor
struct BrowserCoverSourcesTests {
    static func main() async throws {
        await cooldown()
        await rememberedCap()
        try await sessionFiles()
        try await downloads()
        print("PASS: failure cooldown, remembered-cover cap, newest session file, capped redirect-free fetch")
    }

    static func finder(_ lookups: Lookups, _ clock: Clock) -> BrowserCoverFinder {
        BrowserCoverFinder(
            readSession: { _ in await MainActor.run { lookups.reads += 1; return lookups.session } },
            fetch: { url, _ in await MainActor.run { lookups.replies[url.absoluteString] } },
            now: { clock.date.withLock { $0 } }, sleep: { _ in await Task.yield() }, country: "PL")
    }

    static func cooldown() async {
        let lookups = Lookups()
        let clock = Clock()
        let finder = finder(lookups, clock)
        _ = finder.cover(for: track("Lost"))
        await waitUntil { lookups.reads == BrowserCoverRules.attemptDelays.count }
        await settle()
        _ = finder.cover(for: track("Other"))
        await waitUntil { lookups.reads == 2 * BrowserCoverRules.attemptDelays.count }
        await settle()
        clock.advance(BrowserCoverRules.failureCooldown - 1)
        _ = finder.cover(for: track("Lost"))
        await settle()
        precondition(lookups.reads == 2 * BrowserCoverRules.attemptDelays.count, "a failed track waits out its cooldown")
        clock.advance(2)
        _ = finder.cover(for: track("Lost"))
        await waitUntil { lookups.reads > 2 * BrowserCoverRules.attemptDelays.count }
        finder.reset()
    }

    static func rememberedCap() async {
        let lookups = Lookups()
        let finder = finder(lookups, Clock())
        var found = 0
        finder.onFound = { found += 1 }
        let titles = (0...BrowserCoverRules.rememberedCovers).map { "Song \($0)" }
        for (index, title) in titles.enumerated() {
            let video = String(format: "video%06d", index)
            lookups.session = BrowserCoverSession(savedAt: .distantPast, tabs: [BrowserCoverRules.SessionTab(
                title: "\(title) - YouTube", url: URL(string: "https://www.youtube.com/watch?v=\(video)")!)])
            lookups.replies["https://i.ytimg.com/vi/\(video)/maxresdefault.jpg"] = jpeg()
            _ = finder.cover(for: track(title))
            await waitUntil { found == index + 1 }
        }
        precondition(finder.cover(for: track(titles.last!))?.artwork != nil, "the newest cover stays remembered")
        let reads = lookups.reads
        precondition(finder.cover(for: track(titles[1]))?.artwork != nil && lookups.reads == reads,
                     "covers inside the cap return without a lookup")
        precondition(finder.cover(for: track(titles[0]))?.artwork == nil, "the oldest cover past the cap is forgotten")
        await waitUntil { lookups.reads > reads }
        finder.reset()
    }

    static func sessionFiles() async throws {
        let support = FileManager.default.temporaryDirectory.appending(path: "nc-cover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }
        let profiles = support.appending(path: "zen/Profiles")
        let old = profiles.appending(path: "a/sessionstore.jsonlz4")
        let new = profiles.appending(path: "b/sessionstore-backups/recovery.jsonlz4")
        for (file, data) in [(old, session("Old", "aaaaaaaaaaa")), (new, session("New", "bbbbbbbbbbb"))] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        let saved = Date(timeIntervalSince1970: 2_000_000_000)
        let older = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: older], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: saved], ofItemAtPath: new.path)
        let read = await BrowserCoverSources.readSession(bundleID: "app.zen-browser.zen", in: support)
        precondition(read?.savedAt == saved && read?.tabs.map(\.title) == ["New - YouTube"],
                     "the newest session file is the one read, with its YouTube tabs")
        let safari = await BrowserCoverSources.readSession(bundleID: "com.apple.Safari", in: support)
        precondition(safari == nil, "a browser without a Firefox-family profile reads nothing")
        let handle = try FileHandle(forWritingTo: new)
        try handle.truncate(atOffset: UInt64(BrowserCoverRules.maximumSessionFileBytes + 1))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: saved], ofItemAtPath: new.path)
        let oversized = await BrowserCoverSources.readSession(bundleID: "app.zen-browser.zen", in: support)
        precondition(oversized == nil, "an oversized newest session file is never read")
    }

    static func downloads() async throws {
        let server = try Server()
        let base = await server.base()
        let fetch = { (path: String) in await BrowserCoverSources.fetch(URL(string: base + path)!, accept: "image/jpeg") }
        let cover = await fetch("/cover")
        precondition(cover == Data("cover".utf8), "a 200 reply is returned whole")
        precondition(server.requests.withLock { $0.last?.accept } == "image/jpeg", "the request names what it accepts")
        let redirected = await fetch("/redirect")
        precondition(redirected == nil, "a redirect is refused")
        precondition(server.requests.withLock { $0.map(\.path) } == ["/cover", "/redirect"],
                     "a refused redirect never reaches its target")
        for (path, why) in [("/missing", "a non-200 reply reads as nothing"),
                            ("/declared", "a declared length past the cap is refused"),
                            ("/streamed", "an undeclared body past the cap is cut off")] {
            let body = await fetch(path)
            precondition(body == nil, why)
        }
        server.listener.cancel()
    }

    static func jpeg() -> Data {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("timed out")
    }
}
