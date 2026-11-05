#if DEBUG
import AppKit
import SwiftUI

/// Debug only: both visualizers playing side by side in the closed music pill, for picking the closed style.
/// Run the Debug app's executable with `NOTCHCAST_VISUALIZER_LAB=1`.
@MainActor
enum IslandVisualizerLab {
    static func bootIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["NOTCHCAST_VISUALIZER_LAB"] == "1" else { return false }
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let window = NSWindow(contentViewController: NSHostingController(rootView: IslandVisualizerLabView()))
        window.title = "Visualizer Lab"
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate()
        application.run()
        return true
    }
}

struct IslandVisualizerLabView: View {
    @State private var playing = true

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.lg) {
                ForEach(IslandVisualizer.Style.allCases, id: \.self) { style in
                    VStack(spacing: Theme.Spacing.sm) {
                        pill(style)
                        Text(verbatim: style == .orion ? "Orion" : "Damian Tools")
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            Toggle(isOn: $playing) { Text(verbatim: "Playing") }
                .toggleStyle(.switch)
        }
        .padding(Theme.Spacing.xl)
    }

    private func pill(_ style: IslandVisualizer.Style) -> some View {
        HStack(spacing: NotchcastTheme.Closed.itemGap) {
            IslandArtwork(image: nil)
            IslandLines(title: "Teardrop", detail: "Massive Attack")
            Spacer(minLength: NotchcastTheme.Closed.trailingGap)
            IslandVisualizer(isPlaying: playing, style: style)
        }
        .padding(.leading, (NotchcastTheme.Closed.row - NotchcastTheme.Closed.artwork) / 2)
        .padding(.trailing, NotchcastTheme.Closed.textInset)
        .frame(width: NotchcastTheme.Visualizer.labTile.width, height: NotchcastTheme.Closed.row)
        .background(NotchcastTheme.Colors.surface, in: Capsule())
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: style == .orion ? "Orion visualizer" : "Damian Tools visualizer"))
    }
}
#endif
