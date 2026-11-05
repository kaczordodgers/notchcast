import SwiftUI

/// The pieces every closed state is built from, in the launcher's own measures (rules.md, Pieces). Nothing here
/// knows a state: a state is a row of these.
enum IslandPieces {}

/// A glyph in the menu icon slot; white unless the state is an error or a warning.
struct IslandGlyph: View {
    enum Tone { case plain, danger, warning }
    let name: String
    var tone: Tone = .plain

    var body: some View {
        SymbolImage(name: name, size: NotchcastTheme.Pill.symbol)
            .foregroundStyle(tone == .danger ? NotchcastTheme.Colors.danger
                             : tone == .warning ? NotchcastTheme.Colors.warning : NotchcastTheme.Colors.primary)
            .frame(width: NotchcastTheme.Pill.glyph, height: NotchcastTheme.Pill.glyph)
            .accessibilityHidden(true)
    }
}

/// The spinner a state shows while it knows nothing better: the message HUD's own.
struct IslandSpinner: View {
    var body: some View {
        SymbolImage(name: "progress.indicator", size: NotchcastTheme.Pill.symbol)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
            .foregroundStyle(NotchcastTheme.Colors.primary)
            .frame(width: NotchcastTheme.Pill.glyph, height: NotchcastTheme.Pill.glyph)
            .accessibilityHidden(true)
    }
}

/// A state's value, in the row's trailing type with still digits; a percent keeps the volume HUD's readout slot.
struct IslandValueView: View {
    let value: IslandActivity.Value
    var font = NotchcastTheme.Typography.activityValue

    var body: some View {
        Group {
            switch value {
            case let .timeLeft(date):
                Text(date, style: .timer)
            case let .elapsed(since):
                Text(since, style: .timer)
            case let .percent(fraction):
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .frame(width: NotchcastTheme.Pill.readout, alignment: .trailing)
            case let .count(done, of: total), let .step(done, of: total):
                Text(verbatim: "\(done)/\(total)")
            case let .number(text):
                Text(text)
            case let .onOff(on):
                Text(on ? String(localized: "On") : String(localized: "Off"))
            case .spinner:
                IslandSpinner()
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(NotchcastTheme.Colors.primary)
        .lineLimit(1)
        .fixedSize()
    }
}

/// The state's name, in the bar's type.
struct IslandWord: View {
    let text: String
    var secondary = false

    var body: some View {
        Text(text)
            .font(NotchcastTheme.Typography.activityWord)
            .foregroundStyle(secondary ? NotchcastTheme.Colors.secondary : NotchcastTheme.Colors.primary)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The album cover at the row icon's size, or a quiet note; round in the bubble, concentric there.
struct IslandArtwork: View {
    let image: NSImage?
    var round = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                SymbolImage(name: "music.note", size: NotchcastTheme.Pill.symbol)
                    .foregroundStyle(NotchcastTheme.Colors.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NotchcastTheme.Colors.placeholder)
            }
        }
        .frame(width: NotchcastTheme.Pill.artwork, height: NotchcastTheme.Pill.artwork)
        .clipShape(RoundedRectangle(cornerRadius: round ? NotchcastTheme.Pill.artwork / 2
                                        : NotchcastTheme.Corners.artwork, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Title over artist, one line each; a title past the limit scrolls (look-decisions, Music).
struct IslandTrackText: View {
    let title: String
    let artist: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IslandScrollingText(text: title, font: NotchcastTheme.Typography.pillTitle,
                                limit: NotchcastTheme.Pill.textLimit, scrolls: !reduceMotion)
            if !artist.isEmpty {
                Text(artist)
                    .font(NotchcastTheme.Typography.pillSubtitle)
                    .foregroundStyle(NotchcastTheme.Colors.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: NotchcastTheme.Pill.textLimit, alignment: .leading)
            }
        }
        .fixedSize()
    }
}

/// One line that fits the limit, or runs back and forth behind it at the kit's pace.
struct IslandScrollingText: View {
    let text: String
    let font: Font
    let limit: CGFloat
    let scrolls: Bool
    @State private var width: CGFloat = 0
    @State private var away = false

    var body: some View {
        let overflow = max(0, width - limit)
        Text(text)
            .font(font)
            .foregroundStyle(NotchcastTheme.Colors.primary)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .offset(x: away ? -overflow : 0)
            .frame(width: min(width, limit), alignment: .leading)
            .clipped()
            .onChange(of: overflow > 0 && scrolls, initial: true) { _, moving in
                guard moving else { away = false; return }
                withAnimation(.linear(duration: overflow / NotchcastTheme.Pill.scrollSpeed)
                    .delay(NotchcastTheme.Pill.scrollRest).repeatForever(autoreverses: true)) { away = true }
            }
    }
}

/// Orion's level beside a song: four bars that move while a track plays and rest while it is paused. It is a sign,
/// not a meter: nothing here reads the audio.
struct IslandLevelBars: View {
    let moving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandStillTime) private var stillTime
    @State private var high = false

    private var animates: Bool { moving && !reduceMotion }

    var body: some View {
        HStack(alignment: .center, spacing: NotchcastTheme.MusicBars.gap) {
            ForEach(0..<NotchcastTheme.MusicBars.count, id: \.self) { index in
                Capsule()
                    .fill(NotchcastTheme.Colors.primary)
                    .frame(width: NotchcastTheme.MusicBars.width, height: NotchcastTheme.MusicBars.height)
                    .scaleEffect(y: scale(index))
                    // A pause settles the bars rather than snapping them to rest.
                    .animation(animates || reduceMotion || stillTime != nil ? nil
                        : .easeOut(duration: NotchcastTheme.Motion.contentOut), value: animates)
                    .animation(animates && stillTime == nil ? .easeInOut(duration: NotchcastTheme.MusicBars.cycle)
                        .delay(NotchcastTheme.MusicBars.delays[index]).repeatForever(autoreverses: true) : nil,
                               value: high)
            }
        }
        .frame(height: NotchcastTheme.MusicBars.height)
        // Follows `animates`, so a resumed song restarts the repeating cycle instead of resting at full height.
        .onChange(of: animates, initial: true) { _, moving in high = moving }
        .accessibilityHidden(true)
    }

    private func scale(_ index: Int) -> CGFloat {
        guard animates else { return NotchcastTheme.MusicBars.restingLevel }
        if let stillTime { return Self.level(at: stillTime, index: index) }
        return high ? 1 : NotchcastTheme.MusicBars.lowestLevel
    }

    /// The animation above, solved for one moment: an ease-in-out cycle, reversing, started `delays[index]` late.
    static func level(at time: TimeInterval, index: Int) -> CGFloat {
        let bars = NotchcastTheme.MusicBars.self
        let elapsed = time - bars.delays[index]
        guard elapsed > 0 else { return bars.lowestLevel }
        let cycles = (elapsed / bars.cycle).rounded(.down)
        let eased = IslandCurve.easeInOut(elapsed / bars.cycle - cycles)
        let span = 1 - bars.lowestLevel
        return cycles.truncatingRemainder(dividingBy: 2) == 0 ? bars.lowestLevel + span * eased : 1 - span * eased
    }
}

extension EnvironmentValues {
    /// A fixture's clock: when set, pieces that move draw the moment at this many seconds since they appeared
    /// instead of animating, so a frame can be rendered offscreen from the same curves.
    @Entry var islandStillTime: TimeInterval? = nil
}

/// The timing curves the island's pieces and the surface use, solvable at a moment.
enum IslandCurve {
    /// Core Animation's and SwiftUI's ease-in-out: the cubic Bézier (0.42, 0, 0.58, 1).
    static func easeInOut(_ fraction: Double) -> Double {
        let x = min(1, max(0, fraction))
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            let point = bezier(mid, 0.42, 0.58)
            if point < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, 0, 1)
    }

    private static func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
}

/// A transient message: the HUD pill's glyph and line, a quieter second line when there is a next step. Only
/// danger carries colour.
struct IslandMessageLine: View {
    let message: IslandMessage
    @State private var hovered = false

    var body: some View {
        Group {
            if let cancel = message.onCancel {
                Button(action: cancel) { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel \(message.text)")
            } else {
                content.accessibilityElement(children: .combine)
            }
        }
        .onHover { hovered = $0 }
    }

    private var content: some View {
        HStack(spacing: NotchcastTheme.Pill.artworkGap) {
            if hovered, message.onCancel != nil {
                IslandGlyph(name: "xmark")
            } else if message.isProgress {
                IslandSpinner()
            } else {
                IslandGlyph(name: message.tone == .success ? "checkmark.circle"
                            : (message.tone == .danger ? "exclamationmark.circle" : "info.circle"),
                            tone: message.tone == .danger ? .danger : .plain)
            }
            if let detail = message.detail {
                VStack(alignment: .leading, spacing: 0) {
                    IslandWord(text: message.text)
                    Text(detail)
                        .font(NotchcastTheme.Typography.pillSubtitle)
                        .foregroundStyle(NotchcastTheme.Colors.secondary)
                        .lineLimit(1)
                }
            } else {
                IslandWord(text: message.text)
            }
        }
        .frame(maxWidth: Theme.Size.hudMaxWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A card's one button: the footer's bar button, on a control surface as the black has no glass.
struct IslandActionButton: View {
    let title: String
    let run: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: run) {
            Text(title)
                .font(NotchcastTheme.Typography.activityWord)
                .foregroundStyle(NotchcastTheme.Colors.primary)
                .padding(.horizontal, NotchcastTheme.Card.inset)
                .frame(height: NotchcastTheme.Card.button)
                .contentShape(Capsule())
                .background(hovered ? NotchcastTheme.Colors.controlHover : NotchcastTheme.Colors.control,
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
    }
}

/// An activity as a row: glyph, word, value, and a card's button; or any part of it, for a notch wing or the row
/// under the camera (`card` = word and button).
struct IslandActivityLine: View {
    enum Part { case glyph, value, row, card }
    let activity: IslandActivity
    var part: Part = .row

    var body: some View {
        HStack(spacing: NotchcastTheme.Pill.gap) {
            if part == .row {
                HStack(spacing: NotchcastTheme.Pill.artworkGap) {
                    IslandGlyph(name: activity.symbol ?? Self.symbol(for: activity.kind))
                    IslandWord(text: activity.title)
                }
            } else if part == .glyph {
                IslandGlyph(name: activity.symbol ?? Self.symbol(for: activity.kind))
            } else if part == .card {
                IslandWord(text: activity.title)
            }
            if part == .row || part == .value, let value = activity.value { IslandValueView(value: value) }
            if part == .row || part == .card, let action = activity.action {
                IslandActionButton(title: action) { IslandActivityCenter.shared.perform(activity.id) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(activity.title)
    }

    static func symbol(for kind: IslandActivity.Kind) -> String {
        switch kind {
        case .timer: "timer"
        case .transfer: "arrow.down.circle"
        case .status: "info.circle"
        }
    }
}

/// A song as a row: cover, title over artist, bars; or one part, for a notch wing or the bubble.
struct IslandMusicLine: View {
    enum Part { case artwork, bars, row, bubble }
    let music: IslandClosedState.Music
    var part: Part = .row

    var body: some View {
        HStack(spacing: NotchcastTheme.Pill.artworkGap) {
            if part != .bars { IslandArtwork(image: music.artwork, round: part == .bubble) }
            if part == .row { IslandTrackText(title: music.title, artist: music.artist) }
            if part == .row || part == .bars {
                IslandLevelBars(moving: music.isPlaying)
                    .padding(.leading, part == .row ? NotchcastTheme.Pill.gap - NotchcastTheme.Pill.artworkGap : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(music.isPlaying ? music.title : String(localized: "Paused"))
        .accessibilityValue(music.artist)
    }
}
