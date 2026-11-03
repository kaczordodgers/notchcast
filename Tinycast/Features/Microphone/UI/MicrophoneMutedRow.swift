import SwiftUI

struct MicrophoneMutedRow: View {
    var unmute: () -> Void

    var body: some View {
        MusicAttentionRow(
            title: String(localized: "Microphone Muted"),
            subtitle: String(localized: "Every microphone on this Mac is muted."),
            symbol: "mic.slash.fill", isFailure: true, buttonTitle: "Unmute", action: unmute)
    }
}
