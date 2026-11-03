import SwiftUI

struct MusicIslandWing: View {
    var track: NowPlaying?
    var isLeading: Bool
    var isExternalDisplay = false
    var cameraInUse = false
    var microphoneInUse = false
    var microphoneMuted = false
    var microphoneApps: [String] = []

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isLeading {
                if cameraInUse && !isExternalDisplay { MicrophoneIslandMark(isCamera: true) }
                if let track {
                    HStack(spacing: Theme.Spacing.sm) {
                        MusicArtwork(data: track.artwork, size: isExternalDisplay
                            ? NotchcastTheme.pillCover : NotchcastTheme.closedCover)
                        if isExternalDisplay {
                            Text(track.title).font(Theme.Typography.bar)
                                .lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: NotchcastTheme.pillTitle)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(track.isPlaying
                        ? String(localized: "Playing: \(track.title), \(track.artist)")
                        : String(localized: "Paused: \(track.title), \(track.artist)"))
                }
            } else {
                if let track { MusicBars(isPlaying: track.isPlaying) }
                if cameraInUse && isExternalDisplay { MicrophoneIslandMark(isCamera: true) }
                if microphoneMuted || microphoneInUse {
                    MicrophoneIslandMark(isMuted: microphoneMuted, apps: microphoneApps)
                }
            }
        }
        .foregroundStyle(NotchcastTheme.musicForeground)
        .environment(\.colorScheme, .dark)
    }
}
