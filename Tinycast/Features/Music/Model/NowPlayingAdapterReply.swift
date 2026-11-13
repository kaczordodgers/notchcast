import Foundation

enum NowPlayingAdapterReply: Equatable, Sendable {
    enum Failure: Error, Equatable, Sendable {
        case unavailable
        case invalidReply
        case oversizedReply
        case commandRejected
        case unsupportedCommand
    }

    case playback(NowPlaying, pid: Int32)
    case idle
    case command(Bool)

    private typealias Wire = NowPlayingAdapterWire
    private static let maximumArtworkBytes = Wire.maximumArtworkBytes
    static let maximumLineBytes = 4 * ((maximumArtworkBytes + 2) / 3) + 65_536

    static func parse(_ data: Data, previous: NowPlaying?, now: Date) throws -> Self {
        guard data.count <= maximumLineBytes else { throw Failure.oversizedReply }
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.invalidReply
        }
        if reply[Wire.error] != nil { throw Failure.unavailable }
        if let sent = boolean(reply[Wire.sent]) { return .command(sent) }
        func value(_ field: Wire.Info) -> Any? { reply[field.key] ?? reply["_" + field.key] }
        let title = (value(.title) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .idle }
        let bundleID = reply[Wire.displayID] as? String
        let duration = max(0, number(value(.duration)) ?? 0)
        var elapsed = max(0, number(value(.elapsedTime)) ?? 0)
        if duration > 0 { elapsed = min(duration, elapsed) }
        let playing = boolean(reply[Wire.isPlaying]) ?? ((number(value(.playbackRate)) ?? 0) > 0)
        let artist = value(.artist) as? String ?? ""
        let album = value(.album) as? String ?? ""
        var artwork: Data?
        if let encoded = reply[Wire.artworkBase64] as? String,
           encoded.utf8.count <= 4 * ((maximumArtworkBytes + 2) / 3),
           let decoded = Data(base64Encoded: encoded), !decoded.isEmpty, decoded.count <= maximumArtworkBytes {
            artwork = decoded
        } else if boolean(reply[Wire.artworkUnchanged]) == true,
                  previous?.bundleID == bundleID, previous?.title == title,
                  previous?.artist == artist, previous?.album == album,
                  let cached = previous?.artwork, cached.count <= maximumArtworkBytes {
            artwork = cached
        }
        let pid = number(reply[Wire.pid]).flatMap(Int32.init(exactly:)).flatMap { $0 > 0 ? $0 : nil } ?? 0
        return .playback(NowPlaying(
            title: title, artist: artist, album: album,
            app: reply[Wire.displayName] as? String ?? bundleID ?? "", bundleID: bundleID,
            duration: duration, elapsed: elapsed, stamp: now, isPlaying: playing,
            artwork: artwork, origin: .system,
            shuffle: number(value(.shuffleMode)).flatMap { mode in
                switch mode {
                case 1: false
                case 2, 3: true
                default: nil
                }
            },
            repeatMode: number(value(.repeatMode)).flatMap { mode in
                switch mode {
                case 1: .off
                case 2: .one
                case 3: .all
                default: nil
                }
            },
            playbackRate: max(0, number(value(.playbackRate)) ?? 1)
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
