import SwiftUI

struct MusicPlayerCard: View {
    var track: NowPlaying
    var canSeek = true
    var canPrevious = true
    var canTogglePlayback = true
    var canNext = true
    var send: (PlayerCommand) -> Void
    var openPlayer: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            if track.origin == .system, track.bundleID != nil {
                Button(action: openPlayer) { artwork }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(track.app)")
                    .tooltip(String(localized: "Open \(track.app)"))
            } else {
                artwork
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(track.title).font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !track.artist.isEmpty {
                    Text(track.artist).font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Label {
                    if track.origin == .soloist { Text(String(localized: "Spotify Connect")) } else { Text(track.app) }
                } icon: {
                    SymbolImage(name: track.origin == .soloist ? "hifispeaker.fill" : "music.note",
                                size: Theme.Typography.menuSymbolSize, monochrome: true)
                }
                .font(.caption).foregroundStyle(Theme.Colors.textTertiary)
            }
            .lineLimit(1).truncationMode(.tail)
            .frame(width: NotchcastTheme.playerText, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(track.isPlaying
                ? String(localized: "Playing: \(track.title), \(track.artist)")
                : String(localized: "Paused: \(track.title), \(track.artist)"))
            .accessibilityValue(track.origin == .soloist ? String(localized: "Spotify Connect") : track.app)
            if canSeek && track.duration > 0 {
                MusicSeekRow(track: track, send: send)
            } else {
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.Spacing.xxs) {
                control("backward.fill", title: String(localized: "Previous Track"),
                        command: .previous, enabled: canPrevious)
                control(track.isPlaying ? "pause.fill" : "play.fill",
                        title: track.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                        command: .togglePlayPause, enabled: canTogglePlayback)
                    .tooltip(keyCaps: ["Space"])
                control("forward.fill", title: String(localized: "Next Track"),
                        command: .next, enabled: canNext)
            }
        }
        .padding(Theme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: NotchcastTheme.cardRadius, style: .continuous)
                .fill(Theme.Colors.cardFill)
                .strokeBorder(Theme.Colors.cardStroke)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now Playing")
    }

    private var artwork: some View {
        MusicArtwork(data: track.artwork, size: NotchcastTheme.playerCover)
    }

    private func control(_ symbol: String, title: String, command: PlayerCommand, enabled: Bool) -> some View {
        BarButton(isCompact: true, action: { send(command) }) {
            SymbolImage(name: symbol, size: Theme.Radius.dialogSymbol, monochrome: true)
                .frame(width: Theme.Radius.dialogSymbol, height: Theme.Radius.dialogSymbol)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityLabel(title).tooltip(title)
        .disabled(!enabled).opacity(enabled ? 1 : NotchcastTheme.disabledControlOpacity)
    }
}
