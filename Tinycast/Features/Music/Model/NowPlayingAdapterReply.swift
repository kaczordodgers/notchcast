import Foundation

enum NowPlayingAdapterReply: Equatable, Sendable {
    enum Failure: Error, Equatable, Sendable {
        case unavailable
        case invalidReply
        case oversizedReply
        case commandRejected
    }

    case playback(NowPlaying, pid: Int32)
    case idle
    case command(Bool)

    static let maximumArtworkBytes = 12 * 1_024 * 1_024
    static let maximumLineBytes = 4 * ((maximumArtworkBytes + 2) / 3) + 65_536

    static func parse(_ data: Data, previous: NowPlaying?, now: Date) throws -> Self {
        guard data.count <= maximumLineBytes else { throw Failure.oversizedReply }
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.invalidReply
        }
        if reply["error"] != nil { throw Failure.unavailable }
        if let sent = boolean(reply["sent"]) { return .command(sent) }
        func value(_ suffix: String) -> Any? {
            let key = "kMRMediaRemoteNowPlayingInfo\(suffix)"
            return reply[key] ?? reply["_" + key]
        }
        let title = (value("Title") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .idle }
        let bundleID = reply["displayID"] as? String
        let duration = max(0, number(value("Duration")) ?? 0)
        var elapsed = max(0, number(value("ElapsedTime")) ?? 0)
        if duration > 0 { elapsed = min(duration, elapsed) }
        let playing = boolean(reply["isPlaying"]) ?? ((number(value("PlaybackRate")) ?? 0) > 0)
        let artist = value("Artist") as? String ?? ""
        let album = value("Album") as? String ?? ""
        var artwork: Data?
        if let encoded = reply["artworkBase64"] as? String,
           encoded.utf8.count <= 4 * ((maximumArtworkBytes + 2) / 3),
           let decoded = Data(base64Encoded: encoded), !decoded.isEmpty, decoded.count <= maximumArtworkBytes {
            artwork = decoded
        } else if boolean(reply["artworkUnchanged"]) == true,
                  previous?.bundleID == bundleID, previous?.title == title,
                  previous?.artist == artist, previous?.album == album,
                  let cached = previous?.artwork, cached.count <= maximumArtworkBytes {
            artwork = cached
        }
        let pid = number(reply["pid"]).flatMap(Int32.init(exactly:)).flatMap { $0 > 0 ? $0 : nil } ?? 0
        return .playback(NowPlaying(
            title: title, artist: artist, album: album,
            app: reply["displayName"] as? String ?? bundleID ?? "", bundleID: bundleID,
            duration: duration, elapsed: elapsed, stamp: now, isPlaying: playing,
            artwork: artwork, origin: .system
        ), pid: pid)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    struct Lines: Sendable {
        private var pending = Data()

        mutating func append(_ chunk: Data) throws -> [Data] {
            var lines: [Data] = []
            var start = chunk.startIndex
            while let end = chunk[start...].firstIndex(of: 10) {
                guard pending.count + end - start <= maximumLineBytes else { throw Failure.oversizedReply }
                pending.append(chunk[start..<end])
                if !pending.isEmpty { lines.append(pending) }
                pending = Data()
                start = chunk.index(after: end)
            }
            guard pending.count + chunk.endIndex - start <= maximumLineBytes else { throw Failure.oversizedReply }
            pending.append(chunk[start...])
            return lines
        }
    }
}
