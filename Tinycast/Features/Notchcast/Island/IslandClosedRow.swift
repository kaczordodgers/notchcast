import SwiftUI

/// The three parts of every closed item: a leading mark, its lines, a trailing value or action. Both shapes take
/// these and nothing else.
@MainActor
struct IslandItemParts {
    let item: IslandClosedItem
    var onButtonFrame: (CGRect) -> Void = { _ in }

    /// How tall the leading mark is, so the pill's end centres it on its cap.
    var leadingHeight: CGFloat {
        switch item {
        case .music: NotchcastTheme.Closed.artwork
        case .card(let card):
            if case .meeting = card.kind { Theme.Size.calendarBarHeight } else { NotchcastTheme.Closed.glyph }
        case .activity, .message: NotchcastTheme.Closed.glyph
        }
    }

    /// A trailing button is centred on the cap; text and bars keep the text inset.
    var trailingInset: CGFloat {
        if case .card(let card) = item, card.action != nil {
            return (NotchcastTheme.Closed.row - NotchcastTheme.Closed.button) / 2
        }
        return NotchcastTheme.Closed.textInset
    }

    @ViewBuilder var leading: some View {
        switch item {
        case .activity(let activity):
            // Work without a number spins in the glyph slot, like Tinycast's progress HUD: one moving thing.
            if Self.isWorking(activity) {
                IslandGlyph(symbol: "progress.indicator", tone: activity.tone, spinning: true)
            } else {
                IslandGlyph(symbol: activity.shownSymbol, tone: activity.tone)
            }
        case .music(let track):
            IslandArtwork(image: track.artwork)
        case .message(let message):
            IslandGlyph(symbol: message.shownSymbol, tone: Self.tone(message.tone), spinning: message.isProgress)
        case .card(let card):
            switch card.kind {
            case .meeting(_, let color): CalendarBar(color: color)
            case .timerEnd: IslandGlyph(symbol: "timer")
            }
        }
    }

    var title: String {
        switch item {
        case .activity(let activity): activity.title
        case .music(let track): track.title
        case .message(let message): message.text
        case .card(let card): card.title
        }
    }

    @ViewBuilder var lines: some View {
        switch item {
        case .activity(let activity): IslandLines(title: activity.title)
        case .music(let track): IslandLines(title: track.title, detail: track.artist)
        case .message(let message): IslandLines(title: message.text, detail: message.detail)
        case .card(let card):
            switch card.kind {
            case .meeting(let start, _):
                IslandLines(title: card.title, detailView: AnyView(TimelineView(.everyMinute) { context in
                    Text(UpcomingWindow.countdown(to: start, now: context.date, locale: .current))
                }))
            case .timerEnd:
                IslandLines(title: card.title, detailView: AnyView(Text("Done")))
            }
        }
    }

    /// The trailing value, visualizer or button; nil when the item has none.
    @ViewBuilder func trailing(compact: Bool) -> some View {
        switch item {
        case .activity(let activity):
            if Self.hasValue(activity) { IslandValueText(value: activity.shownValue, compact: compact) }
        case .music(let track): IslandVisualizer(isPlaying: track.isPlaying)
        case .message(let message):
            if let value = message.value { IslandValueText(value: value, compact: compact) }
        case .card(let card):
            if let action = card.action {
                switch card.kind {
                case .meeting: IslandCardButton(title: "Join", action: action, onFrame: onButtonFrame)
                case .timerEnd: IslandCardButton(title: "Stop", action: action, onFrame: onButtonFrame)
                }
            }
        }
    }

    var hasTrailing: Bool {
        switch item {
        case .message(let message): message.value != nil
        case .card(let card): card.action != nil
        case .activity(let activity): Self.hasValue(activity)
        case .music: true
        }
    }

    /// A spinner is no value: it moves into the glyph. A status with nothing to count shows its glyph alone.
    static func hasValue(_ activity: IslandActivity) -> Bool { activity.shownValue != .spinner }

    static func isWorking(_ activity: IslandActivity) -> Bool {
        activity.shownValue == .spinner && (activity.value != nil || activity.kind != .status)
    }

    static func tone(_ tone: IslandMessage.Tone) -> IslandActivity.Tone {
        switch tone {
        case .neutral, .success: .plain
        case .warning: .warning
        case .danger: .error
        }
    }
}

/// One closed row: the island's pill, and every row below the camera. On the island its ends follow the capsule's
/// caps; below the camera the body's own side inset holds it.
struct IslandClosedRow: View {
    let parts: IslandItemParts
    var showsLeading = true
    var capsuleEnds = true

    var body: some View {
        HStack(spacing: NotchcastTheme.Closed.itemGap) {
            // Below the camera rows stack, so every mark takes the cover's width and the text starts on one line.
            if showsLeading {
                parts.leading.frame(width: capsuleEnds ? nil : NotchcastTheme.Closed.artwork)
            }
            parts.lines
            if parts.hasTrailing {
                Spacer(minLength: NotchcastTheme.Closed.trailingGap)
                parts.trailing(compact: false)
            }
        }
        .padding(.leading, capsuleEnds && showsLeading
                 ? (NotchcastTheme.Closed.row - parts.leadingHeight) / 2 : NotchcastTheme.Closed.dropInset)
        .padding(.trailing, capsuleEnds ? parts.trailingInset : NotchcastTheme.Closed.dropInset)
        .frame(height: NotchcastTheme.Closed.row)
        // The pill takes its content's width; a row below the camera spans the body like a launcher row.
        .fixedSize(horizontal: capsuleEnds, vertical: true)
        .frame(maxWidth: capsuleEnds ? nil : .infinity, alignment: .leading)
    }
}

/// The second thing beside the island: its leading mark alone, in a bubble of the pill's height.
struct IslandBubble: View {
    let parts: IslandItemParts

    var body: some View {
        parts.leading
            .frame(width: NotchcastTheme.Closed.bubble, height: NotchcastTheme.Closed.bubble)
            .accessibilityElement()
            .accessibilityLabel(parts.title)
    }
}
