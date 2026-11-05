import AppKit
import SwiftUI

/// Debug only: both candidate levels playing side by side in one black row, so the one that fits Tinycast can be
/// picked (look-decisions, Music: Visualizer). Orion's four bars left, Damian Tools' seven right. The row is the
/// island's own capsule, over black, in a floating panel under the pointer's screen.
@MainActor
enum IslandVisualizerComparison {
    nonisolated static let command = NotchcastCommand(
        slug: "compare-visualizers", name: String(localized: "Compare Visualizers", table: "Notchcast"),
        sfSymbol: "waveform", feature: .island,
        isEnabled: { isDebug }, run: { show() })

    private static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static var panel: NSPanel?

    static func show() {
        #if DEBUG
        let panel = panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            let size = panel.frame.size
            panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2,
                                         y: screen.frame.maxY - NotchcastTheme.Pill.topGap - size.height
                                            - NotchcastTheme.rowHeight * 2))
        }
        panel.orderFrontRegardless()
        #endif
    }

    #if DEBUG
    private static func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: AnyView(IslandVisualizerComparisonView().motionScope()))
        hosting.sizingOptions = [.intrinsicContentSize]
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        return panel
    }
    #endif
}

/// One row per candidate, each the music pill as it would ship with that level, then both levels large.
struct IslandVisualizerComparisonView: View {
    var isPlaying = true
    var visibleOverride: Bool? = nil

    var body: some View {
        let song = IslandClosedState.Music(title: "Teardrop", artist: "Massive Attack", artwork: nil, isPlaying: isPlaying)
        VStack(spacing: NotchcastTheme.Pill.bubbleGap) {
            HStack(spacing: NotchcastTheme.Pill.bubbleGap) {
                pill {
                    IslandArtwork(image: song.artwork)
                    IslandTrackText(title: song.title, artist: song.artist)
                    IslandLevelBars(moving: isPlaying).padding(.leading, NotchcastTheme.Pill.gap - NotchcastTheme.Pill.artworkGap)
                }
                pill {
                    IslandArtwork(image: song.artwork)
                    IslandTrackText(title: song.title, artist: song.artist)
                    IslandSpectrumBars(isPlaying: isPlaying, visibleOverride: visibleOverride)
                        .padding(.leading, NotchcastTheme.Pill.gap - NotchcastTheme.Pill.artworkGap)
                }
            }
            HStack(spacing: NotchcastTheme.Pill.bubbleGap) {
                pill {
                    IslandWord(text: "Orion", secondary: true)
                    IslandLevelBars(moving: isPlaying)
                }
                pill {
                    IslandWord(text: "Damian Tools", secondary: true)
                    IslandSpectrumBars(isPlaying: isPlaying, visibleOverride: visibleOverride)
                }
            }
        }
        .padding(NotchcastTheme.Pill.bubbleGap)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(String(localized: "Compare Visualizers", table: "Notchcast"))
    }

    private func pill(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: NotchcastTheme.Pill.artworkGap, content: content)
            .padding(.horizontal, NotchcastTheme.Pill.inset)
            .frame(height: NotchcastTheme.rowHeight)
            .background(NotchcastTheme.Colors.surface, in: Capsule())
    }
}
