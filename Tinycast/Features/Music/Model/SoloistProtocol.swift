import Foundation

enum SoloistProtocol {
    struct AuthState: Codable, Equatable, Sendable {
        var loggedIn: Bool
        var isActive: Bool
        var deviceName: String
    }

    enum Message: Equatable, Sendable {
        case state(NowPlaying?, cover: URL?)
        case auth(AuthState)
        case changed
        case failure(String)
        case other
    }

    struct Command: Encodable, Sendable {
        var type = "command"
        var command: String
        var position_ms: Double?
        var volume: Int?
    }

    private struct Entity: Decodable {
        var decorations: Decorations?
        final class Related: Decodable { var entity: Entity }
        struct Decorations: Decodable {
            var identity: Identity?
            var creators: [Related]?
            var parent: Related?
            var playback: Playback?
            var visualIdentity: VisualIdentity?
        }
        struct Identity: Decodable { var name: String? }
        struct Playback: Decodable { var durationMs: Double? }
        struct VisualIdentity: Decodable { var cover: [Cover]? }
        struct Cover: Decodable { var url: URL; var size: String? }
    }

    private struct Frame: Decodable {
        var type: String
        var message: String?
        var status: String?
        var item: Entity?
        var position: Position?
        var isActive: Bool?
        struct Position: Decodable {
            var positionMs: Double?
            var timestampMs: Double?
        }
    }

    static func parse(_ text: String, now: Date) throws -> Message {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = Data(text.utf8)
        let frame = try decoder.decode(Frame.self, from: data)
        switch frame.type {
        case "error": return .failure(frame.message ?? "")
        case "auth_state": return .auth(try decoder.decode(AuthState.self, from: data))
        case "playback_state":
            guard frame.status != "idle", let details = frame.item?.decorations,
                  let title = details.identity?.name else { return .state(nil, cover: nil) }
            let covers = details.visualIdentity?.cover ?? []
            let cover = (covers.first { $0.size == "default" } ?? covers.first)?.url
            let stamp = frame.position?.timestampMs.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
            let track = NowPlaying(
                title: title,
                artist: (details.creators ?? []).compactMap { $0.entity.decorations?.identity?.name }.joined(separator: ", "),
                album: details.parent?.entity.decorations?.identity?.name ?? "",
                app: "Spotify", bundleID: nil,
                duration: max(0, details.playback?.durationMs ?? 0) / 1000,
                elapsed: max(0, frame.position?.positionMs ?? 0) / 1000,
                stamp: min(stamp, now), isPlaying: frame.status == "playing" && frame.isActive != false,
                artwork: nil, origin: .soloist
            )
            return .state(track, cover: cover)
        case "track_changed", "playback_changed", "position_sync", "queue_changed",
             "device_changed", "context_changed", "options_changed", "volume_changed": return .changed
        default: return .other
        }
    }

    static func encode(_ command: PlayerCommand, isPlaying: Bool) throws -> String {
        let value: Command
        switch command {
        case .play: value = Command(command: "play")
        case .pause: value = Command(command: "pause")
        case .togglePlayPause: value = Command(command: isPlaying ? "pause" : "play")
        case .next: value = Command(command: "skip_next")
        case .previous: value = Command(command: "skip_prev")
        case .seek(let seconds):
            value = Command(command: "seek", position_ms: seconds.isFinite ? (max(0, seconds) * 1000).rounded() : 0)
        case .volume(let level):
            value = Command(command: "set_volume", volume: level.isFinite ? Int((min(1, max(0, level)) * 100).rounded()) : 0)
        }
        return String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }

    static let getState = #"{"type":"command","command":"get_state"}"#
    static let getAuthState = #"{"type":"command","command":"get_auth_state"}"#
}
