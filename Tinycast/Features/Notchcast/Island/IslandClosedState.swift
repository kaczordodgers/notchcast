import AppKit

/// A song as the closed island shows it.
struct IslandTrack: Equatable {
    var title: String
    var artist: String
    var artwork: NSImage?
    var isPlaying: Bool
}

/// A closed state that asks for one action: a meeting to join, a timer to stop.
struct IslandCard {
    enum Kind {
        case meeting(start: Date, color: MeetingEvent.CalendarColor?)
        case timerEnd
    }

    let kind: Kind
    let title: String
    /// Nil hides the button: a meeting without a link has nothing to join.
    let action: (() -> Void)?
}

enum IslandClosedItem {
    case activity(IslandActivity)
    case music(IslandTrack)
    case message(IslandMessage)
    case card(IslandCard)
}

/// What a closed island shows: nothing, one thing, or a main thing and a second one (look-decisions, Cards:
/// notch one below the other, island the main one plus a small bubble).
struct IslandClosedState {
    var main: IslandClosedItem?
    var second: IslandClosedItem?

    static var idle: Self { Self() }

    var isIdle: Bool { main == nil }

    /// The text VoiceOver reads for the closed island.
    var spokenSummary: String? {
        main.map(Self.spoken)
    }

    private static func spoken(_ item: IslandClosedItem) -> String {
        switch item {
        case .activity(let activity): activity.title
        case .music(let track): track.artist.isEmpty ? track.title : "\(track.title), \(track.artist)"
        case .message(let message): [message.text, message.detail].compactMap { $0 }.joined(separator: ", ")
        case .card(let card): card.title
        }
    }
}
