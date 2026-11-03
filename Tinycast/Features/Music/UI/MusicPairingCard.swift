import SwiftUI

struct MusicPairingCard: View {
    var deviceName: String

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            MusicArtwork(size: NotchcastTheme.playerCover, symbol: "hifispeaker.fill",
                         symbolSize: NotchcastTheme.pairingSymbol, symbolColor: Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("Pick “\(deviceName)” in Spotify").font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("In Spotify on your phone or computer, choose this Mac as the speaker.")
                    .font(Theme.Typography.rowTrailing).foregroundStyle(Theme.Colors.textSecondary)
                Label { Text(String(localized: "Spotify Connect")) } icon: {
                    SymbolImage(name: "hifispeaker.fill", size: Theme.Typography.menuSymbolSize, monochrome: true)
                }
                    .font(.caption).foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: NotchcastTheme.cardRadius, style: .continuous)
                .fill(Theme.Colors.cardFill).strokeBorder(Theme.Colors.cardStroke)
        }
        .accessibilityElement(children: .combine)
    }
}
