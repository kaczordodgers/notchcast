import SwiftUI

struct MicrophoneIslandMark: View {
    var isCamera = false
    var isMuted = false
    var apps: [String] = []

    var body: some View {
        SymbolImage(
            name: isCamera ? "video.fill" : isMuted ? "mic.slash.fill" : "mic.fill",
            size: Theme.Typography.menuSymbolSize, monochrome: true
        )
        .foregroundStyle(isCamera ? Theme.Colors.success : isMuted
            ? Theme.Colors.destructive : Theme.Colors.warning)
        .accessibilityLabel(label)
    }

    private var label: String {
        if isCamera { return String(localized: "Camera in use") }
        if isMuted { return String(localized: "Microphone muted") }
        guard !apps.isEmpty else { return String(localized: "Microphone in use") }
        let names = ListFormatter.localizedString(byJoining: apps)
        return String(localized: "Microphone in use by \(names)")
    }
}
