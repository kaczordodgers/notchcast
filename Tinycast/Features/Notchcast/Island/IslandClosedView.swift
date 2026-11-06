import SwiftUI

extension EnvironmentValues {
    @Entry var hasHardwareNotch = false
}

/// Every closed state of both shapes. The island is one pill row plus a bubble for a second thing; the notch puts
/// the row's leading mark and trailing value in its wings and every other row below the camera.
struct IslandClosedView: View {
    var hardwareNotch: CGRect?
    var state: IslandClosedState
    /// The body's size: the pill on a monitor, the whole black shape beside a notch.
    var onSize: (CGSize) -> Void
    var onButtonFrame: (CGRect) -> Void = { _ in }
    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0
    @State private var titleWidth: CGFloat = 0

    var body: some View {
        Group {
            if let hardwareNotch { notch(hardwareNotch) } else { island }
        }
        // Fresh views per state restart their onAppear animations; the handover snapshot hides the swap.
        .id(state.key)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(NotchcastTheme.Colors.primary)
        .environment(\.colorScheme, .dark)
        .coordinateSpace(name: "islandClosed")
        .transaction(value: state.key) { $0.animation = nil; $0.disablesAnimations = true }
        .motionScope()
    }

    // MARK: Island

    /// The pill stays centred on the screen; the bubble hangs off its trailing end without moving it.
    private var island: some View {
        Group {
            if let main = state.main {
                IslandClosedContent(parts: IslandItemParts(item: main, onButtonFrame: onButtonFrame))
            } else {
                Color.clear.frame(height: NotchcastTheme.Closed.row)
            }
        }
        .frame(minWidth: NotchcastTheme.Closed.idleWidth, maxWidth: NotchcastTheme.Closed.maximumWidth)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .overlay(alignment: .trailing) {
            if let second = state.second {
                IslandBubble(parts: IslandItemParts(item: second))
                    .offset(x: NotchcastTheme.Closed.bubble + NotchcastTheme.Closed.bubbleGap)
            }
        }
        .padding(.top, NotchcastTheme.Closed.topGap)
    }

    // MARK: Notch

    private func notch(_ camera: CGRect) -> some View {
        VStack(spacing: 0) {
            if let main = state.main {
                let parts = IslandItemParts(item: main, onButtonFrame: onButtonFrame)
                HStack(spacing: 0) {
                    wing { if !needsLines(main) { parts.leading } }
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { leadingWidth = $0 }
                        .frame(width: wingWidth)
                    Color.clear.frame(width: camera.width).accessibilityHidden(true)
                    wing { notchTrailing(parts) }
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trailingWidth = $0 }
                        .frame(width: wingWidth)
                }
                .frame(height: camera.height)
                if needsLines(main) {
                    IslandClosedContent(parts: parts)
                }
                if let second = state.second {
                    IslandClosedContent(parts: IslandItemParts(item: second))
                }
                if needsLines(main) || state.second != nil {
                    Color.clear.frame(height: NotchcastTheme.Closed.dropBottom)
                }
            } else {
                Color.clear.frame(width: camera.width, height: camera.height)
            }
        }
        .padding(.horizontal, state.isIdle ? 0 : NotchcastTheme.Closed.shoulder)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .background(alignment: .topLeading) { titleProbe }
    }

    private func wing(@ViewBuilder _ content: () -> some View) -> some View {
        content().fixedSize().padding(.horizontal, NotchcastTheme.Closed.wingInset)
    }

    private var wingWidth: CGFloat { max(NotchcastTheme.Closed.wing, leadingWidth, trailingWidth) }

    /// A message short enough to sit in the wing stays there; a longer one, or any card, goes below the camera.
    private func needsLines(_ item: IslandClosedItem) -> Bool {
        switch item {
        case .music: false
        case .activity(let activity):
            activity.kind == .transfer || (!IslandItemParts.hasValue(activity)
                && titleWidth > NotchcastTheme.Closed.wingTextLimit)
        case .card: true
        case .message(let message):
            message.value == nil && (message.detail != nil || titleWidth > NotchcastTheme.Closed.wingTextLimit)
        }
    }

    @ViewBuilder
    private func notchTrailing(_ parts: IslandItemParts) -> some View {
        switch parts.item {
        case .activity, .message:
            if needsLines(parts.item) {
                EmptyView()
            } else if !parts.hasTrailing {
                titleText(parts.title)
            } else {
                parts.trailing(compact: true)
            }
        case .music: parts.trailing(compact: true)
        case .card: EmptyView()
        }
    }

    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(NotchcastTheme.Typography.title)
            .lineLimit(1)
            .fixedSize()
    }

    private var titleProbe: some View {
        ZStack {
            if let main = state.main {
                let parts = IslandItemParts(item: main)
                titleText(parts.title)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titleWidth = $0 }
            }
        }
        .hidden()
        .accessibilityHidden(true)
    }
}

extension IslandClosedState {
    /// What changes the layout, so content swaps animate only when the state does.
    var key: String {
        [main, second].map { item -> String in
            switch item {
            case .activity(let activity): "activity-\(activity.id)"
            case .music(let track): "music-\(track.title)-\(track.isPlaying)"
            case .message(let message): "message-\(message.id)-\(message.text)"
            case .card(let card): "card-\(card.title)"
            case nil: "none"
            }
        }.joined(separator: "|")
    }
}
