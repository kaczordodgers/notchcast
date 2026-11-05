import SwiftUI

extension EnvironmentValues {
    @Entry var hasHardwareNotch = false
}

/// The closed states, one layout per shape (rules.md, Layout per state): beside a notch the primary's pieces split
/// into the wings and the next thing takes a row under the camera; on a monitor one capsule holds the primary's row
/// and a bubble holds the next thing's glyph.
struct IslandClosedView: View {
    var context: IslandClosedContext
    var state: IslandClosedState
    var cameraWidth: CGFloat
    var bandHeight: CGFloat
    var message: IslandMessage?
    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0
    var onWidth: (CGFloat) -> Void

    var body: some View {
        Group {
            if cameraWidth > 0 { notch } else { island }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidth($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(NotchcastTheme.Colors.primary)
        .environment(\.colorScheme, .dark)
        .motionScope()
    }

    private var notch: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                wing(leading: true)
                Color.clear.frame(width: cameraWidth).accessibilityHidden(true)
                wing(leading: false)
            }
            .padding(.horizontal, state.isEmpty && message == nil ? 0 : NotchcastTheme.Pill.inset)
            .frame(height: bandHeight)
            if let message {
                IslandMessageLine(message: message)
                    .padding(.horizontal, NotchcastTheme.Pill.inset)
                    .frame(height: NotchcastTheme.rowHeight)
            } else if state.hasSecond {
                secondRow
                    .padding(.horizontal, NotchcastTheme.Pill.inset)
                    .frame(height: NotchcastTheme.rowHeight)
            }
        }
        .fixedSize()
    }

    private var island: some View {
        HStack(spacing: NotchcastTheme.Pill.bubbleGap) {
            Group {
                if let message {
                    IslandMessageLine(message: message)
                } else if let primary = state.primary {
                    IslandActivityLine(activity: primary)
                } else if let music = state.music {
                    IslandMusicLine(music: music)
                } else {
                    Color.clear.frame(width: NotchcastTheme.monitorPill.width - NotchcastTheme.Pill.inset * 2)
                }
            }
            .padding(.horizontal, NotchcastTheme.Pill.inset)
            .frame(height: NotchcastTheme.rowHeight)
            if message == nil, state.hasSecond {
                bubble.frame(width: NotchcastTheme.Pill.bubble, height: NotchcastTheme.Pill.bubble)
            }
        }
        .fixedSize()
    }

    @ViewBuilder private func wing(leading: Bool) -> some View {
        Group {
            if let primary = state.primary {
                IslandActivityLine(activity: primary, part: leading ? .glyph : .value)
            } else if let music = state.music {
                IslandMusicLine(music: music, part: leading ? .artwork : .bars)
            } else {
                Color.clear.frame(width: 0)
            }
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            if leading { leadingWidth = $0 } else { trailingWidth = $0 }
        }
        .frame(width: state.isEmpty ? 0 : wingWidth)
    }

    /// Whatever the primary pushed out of the band: the next activity, or the song behind an activity.
    @ViewBuilder private var secondRow: some View {
        if let second = state.secondary {
            IslandActivityLine(activity: second)
        } else if let music = state.music {
            IslandMusicLine(music: music)
        }
    }

    @ViewBuilder private var bubble: some View {
        if let second = state.secondary {
            IslandActivityLine(activity: second, part: .glyph)
        } else if let music = state.music {
            IslandMusicLine(music: music, part: .artwork)
        }
    }

    private var wingWidth: CGFloat {
        context.wingWidth(contentWidth: max(leadingWidth, trailingWidth), minimum: NotchcastTheme.minimumWing)
    }
}
