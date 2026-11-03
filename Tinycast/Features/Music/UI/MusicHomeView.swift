import SwiftUI

struct MusicHomeView: View {
    var track: NowPlaying?
    var speakerState: SoloistSpeakerState = .off
    var deviceName = "Notchcast"
    var microphoneMuted = false
    var canSeek = true
    var canPrevious = true
    var canTogglePlayback = true
    var canNext = true
    var send: (PlayerCommand) -> Void
    var openPlayer: () -> Void
    var unmute: () -> Void
    var openSettings: () -> Void

    var body: some View {
        if track != nil || microphoneMuted || attention != nil || isPairing {
            content
        }
    }

    private var isPairing: Bool {
        if case .running = speakerState { return true }
        return false
    }

    private var content: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let track {
                MusicPlayerCard(track: track, canSeek: canSeek, canPrevious: canPrevious,
                                canTogglePlayback: canTogglePlayback, canNext: canNext,
                                send: send, openPlayer: openPlayer)
            } else if case .running = speakerState {
                MusicPairingCard(deviceName: deviceName)
            }
            if microphoneMuted { MicrophoneMutedRow(unmute: unmute) }
            if let attention {
                MusicAttentionRow(title: attention.title, subtitle: attention.subtitle,
                                  symbol: attention.failure ? "exclamationmark.circle.fill"
                                    : "exclamationmark.triangle.fill",
                                  isFailure: attention.failure, action: openSettings)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.xs)
        .environment(\.colorScheme, .dark)
    }

    private var attention: (title: String, subtitle: String, failure: Bool)? {
        switch speakerState {
        case .expiresSoon(let days):
            (days == 1 ? String(localized: "Soloist expires tomorrow")
                : String(localized: "Soloist expires in \(days) days"),
             String(localized: "Download it again in Settings to keep Spotify playing here."), false)
        case .noKey:
            (String(localized: "Spotify Connect needs setup"),
             String(localized: "Add your Soloist API key in Settings."), false)
        case .needsBuild:
            (String(localized: "Spotify Connect needs setup"),
             String(localized: "Download Soloist in Settings."), false)
        case .failed(let reason):
            (String(localized: "Spotify Connect stopped"), failureText(reason), true)
        default:
            nil
        }
    }

    private func failureText(_ reason: SoloistFailure) -> String {
        switch reason {
        case .keyUnavailable: String(localized: "Couldn’t read the API key from Keychain.")
        case .invalidKey: String(localized: "Spotify didn’t accept the API key.")
        case .keyFileUnreadable: String(localized: "Couldn’t read that file.")
        case .download: String(localized: "Couldn’t download Soloist. Check your connection.")
        case .httpStatus(let status): String(localized: "Spotify’s download server answered \(status).")
        case .retryAfter(let date):
            String(localized: "Spotify asked to wait. Try again after \(date.formatted(.dateTime.hour().minute())).")
        case .archive, .refusedBuild: String(localized: "The download isn’t a usable Soloist build.")
        case .process: String(localized: "Soloist quit unexpectedly.")
        case .portTimeout: String(localized: "Soloist didn’t respond.")
        case .filesystem: String(localized: "Couldn’t save Soloist’s files.")
        }
    }
}
