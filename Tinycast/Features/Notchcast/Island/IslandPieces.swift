import SwiftUI

/// The pieces every closed state is built from, in both shapes. A state never styles its own text, glyph or value.

/// A state's symbol in the 20-point menu slot: white, red for an error, orange for a warning, a spinner when the
/// work has nothing better to say. One ink for the whole symbol, like the HUD pill's glyph, so no layer greys out;
/// a battery keeps its layers, since its fill against its frame is the level.
struct IslandGlyph: View {
    let symbol: String
    var tone: IslandActivity.Tone = .plain
    var spinning = false

    var body: some View {
        SymbolImage(name: closedSymbol, size: NotchcastTheme.Closed.symbol, monochrome: !symbol.hasPrefix("battery"))
            .foregroundStyle(tint)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, isActive: spinning)
            .frame(width: NotchcastTheme.Closed.glyph, height: NotchcastTheme.Closed.glyph)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch tone {
        case .plain: NotchcastTheme.Colors.primary
        case .warning: NotchcastTheme.Colors.warning
        case .error: NotchcastTheme.Colors.error
        }
    }

    private var closedSymbol: String {
        switch symbol {
        case "sun.max": "sun.max.fill"
        case "info": "info.circle"
        case "exclamationmark": "exclamationmark.circle"
        case "checkmark": "checkmark.circle"
        default: symbol
        }
    }
}

/// The value type, drawn one way everywhere: callout, monospaced digits, white.
struct IslandValueText: View {
    let value: IslandValue
    /// A notch wing drops words ("Step 2/4" reads "2/4").
    var compact = false

    var body: some View {
        content
            .font(NotchcastTheme.Typography.value)
            .monospacedDigit()
            .foregroundStyle(NotchcastTheme.Colors.primary)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch value {
        case .timeLeft(let end):
            Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
        case .elapsed(let start):
            Text(start, style: .timer)
        case .elapsedFrozen(let seconds):
            Text(verbatim: Duration.seconds(seconds).formatted(
                .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond)))
        case .percent(let share):
            Text(share, format: .percent.precision(.fractionLength(0)))
        case .count(let done, let total):
            Text(verbatim: "\(done.formatted())/\(total.formatted())")
        case .step(let done, let total):
            if compact {
                Text(verbatim: "\(done.formatted())/\(total.formatted())")
            } else {
                Text("Step \(done)/\(total)", tableName: "Notchcast")
            }
        case .live(let number, .none):
            Text(number, format: .number.precision(.fractionLength(0)))
        case .live(let number, .megabitsPerSecond):
            Text("\(number.formatted(.number.precision(.fractionLength(0)))) Mb/s", tableName: "Notchcast")
        case .toggle(true):
            Circle()
                .fill(NotchcastTheme.Colors.primary)
                .frame(width: NotchcastTheme.Value.dot, height: NotchcastTheme.Value.dot)
                .accessibilityElement()
                .accessibilityValue(Text("On"))
        case .toggle(false):
            // Off is Tinycast's own word, never a second glyph (design system §9).
            Text("Off")
        case .level(let share):
            IslandOrionBars(moving: false, level: share)
        case .spinner:
            IslandGlyph(symbol: "progress.indicator", spinning: true)
        case .pair(let first, let second):
            HStack(spacing: NotchcastTheme.Closed.itemGap) {
                IslandValueText(value: first, compact: compact)
                IslandValueText(value: second, compact: compact)
            }
        }
    }
}

/// A level as a ring around nothing: the chat's context gauge, for levels in a notch wing.
struct IslandRing: View {
    let share: Double

    var body: some View {
        ZStack {
            Circle().stroke(NotchcastTheme.Colors.control, lineWidth: NotchcastTheme.Value.ringStroke)
            Circle()
                .trim(from: 0, to: share)
                .stroke(NotchcastTheme.Colors.primary,
                        style: StrokeStyle(lineWidth: NotchcastTheme.Value.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: NotchcastTheme.Value.ring, height: NotchcastTheme.Value.ring)
        .accessibilityHidden(true)
    }
}

/// Title, and an optional second line under it: the song and its artist, a message and its description, a
/// meeting and when it starts. The title follows its width up to the limit, then scrolls.
struct IslandLines: View {
    let title: String
    var detail: String?
    var detailView: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: NotchcastTheme.Closed.lineSpacing) {
            IslandScrollingText(text: title)
                .font(NotchcastTheme.Typography.title)
                .foregroundStyle(NotchcastTheme.Colors.primary)
            if let detailView {
                detailView
                    .font(NotchcastTheme.Typography.detail)
                    .foregroundStyle(NotchcastTheme.Colors.secondary)
            } else if let detail, !detail.isEmpty {
                Text(detail)
                    .font(NotchcastTheme.Typography.detail)
                    .foregroundStyle(NotchcastTheme.Colors.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: NotchcastTheme.Closed.titleLimit, alignment: .leading)
                    .fixedSize()
            }
        }
    }
}

/// One line that is as wide as it needs up to the title limit; a longer one scrolls, pausing at the start.
/// Reduce Motion or Show animations off leave it truncated.
struct IslandScrollingText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var scrolled = false

    private var overflows: Bool { width > NotchcastTheme.Closed.titleLimit }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .hidden()
            .frame(width: min(width, NotchcastTheme.Closed.titleLimit), alignment: .leading)
            .overlay(alignment: .leading) {
                if overflows, !reduceMotion, Motion.isEnabled {
                    HStack(spacing: NotchcastTheme.Closed.scrollGap) {
                        Text(text).fixedSize()
                        Text(text).fixedSize()
                    }
                    .offset(x: scrolled ? -(width + NotchcastTheme.Closed.scrollGap) : 0)
                    .animation(.linear(duration: Double((width + NotchcastTheme.Closed.scrollGap)
                                                        / NotchcastTheme.Closed.scrollSpeed))
                        .delay(NotchcastTheme.Closed.scrollPause).repeatForever(autoreverses: false), value: scrolled)
                    .onAppear { scrolled = true }
                    .onDisappear { scrolled = false }
                } else {
                    Text(text).lineLimit(1).truncationMode(.tail)
                }
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}

/// A song's cover, or the music symbol on a control tile while the player gave none.
struct IslandArtwork: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                SymbolImage(name: "music.note", size: NotchcastTheme.Closed.symbol)
                    .foregroundStyle(NotchcastTheme.Colors.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NotchcastTheme.Colors.control)
            }
        }
        .frame(width: NotchcastTheme.Closed.artwork, height: NotchcastTheme.Closed.artwork)
        .clipShape(RoundedRectangle(cornerRadius: NotchcastTheme.Corners.artwork, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A card's one action: a matte capsule concentric with the pill's end, filled at rest, hover and press like
/// Tinycast's matte action buttons (`ModalActionButtonStyle`).
struct IslandCardButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var onFrame: (CGRect) -> Void = { _ in }
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NotchcastTheme.Typography.title)
                .foregroundStyle(NotchcastTheme.Colors.primary)
                .padding(.horizontal, NotchcastTheme.Closed.buttonInset)
                .frame(height: NotchcastTheme.Closed.button)
                .contentShape(Capsule())
        }
        .buttonStyle(IslandCardButtonStyle(hovered: hovered))
        .accessibilityLabel(Text(title))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("islandClosed")) } action: { onFrame($0) }
        .onHover { hovered = $0 }
        .animation(NotchcastTheme.Motion.swap, value: hovered)
    }
}

private struct IslandCardButtonStyle: ButtonStyle {
    let hovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Capsule().fill(
            configuration.isPressed ? NotchcastTheme.Colors.controlPressed
                : hovered ? NotchcastTheme.Colors.controlHover : NotchcastTheme.Colors.control))
    }
}
