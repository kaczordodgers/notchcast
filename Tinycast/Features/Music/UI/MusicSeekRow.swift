import SwiftUI

struct MusicSeekRow: View {
    var track: NowPlaying
    var send: (PlayerCommand) -> Void
    @State private var dragPosition: Double?

    var body: some View {
        Group {
            if track.isPlaying {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    seekRow(at: context.date)
                }
            } else {
                seekRow(at: track.stamp)
            }
        }
        .onChange(of: track) { dragPosition = nil }
    }

    private func seekRow(at date: Date) -> some View {
        let position = dragPosition ?? track.position(at: date)
        return HStack(spacing: Theme.Spacing.sm) {
                Text(verbatim: readout(position))
                    .frame(width: NotchcastTheme.seekReadout, alignment: .trailing)
                Slider(value: Binding(
                    get: { min(track.duration, max(0, position)) },
                    set: { dragPosition = $0 }
                ), in: 0...track.duration) { editing in
                    if !editing, let dragPosition {
                        send(.seek(dragPosition))
                        self.dragPosition = nil
                    }
                }
                .controlSize(.small).tint(Theme.Colors.textPrimary)
                .accessibilityLabel("Position")
                .accessibilityValue("\(spoken(position)) of \(spoken(track.duration))")
                Text(verbatim: readout(track.duration))
                    .frame(width: NotchcastTheme.seekReadout, alignment: .leading)
            }
            .font(Theme.Typography.rowTrailing.monospacedDigit())
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private func readout(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    private func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(width: .wide))
    }
}
