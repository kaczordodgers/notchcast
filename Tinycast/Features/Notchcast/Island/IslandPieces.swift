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
        SymbolImage(name: name, size: NotchcastTheme.Pill.glyph)
            .foregroundStyle(tone == .danger ? NotchcastTheme.Colors.danger
                             : tone == .warning ? NotchcastTheme.Colors.warning : NotchcastTheme.Colors.primary)
            .frame(width: NotchcastTheme.Pill.glyph, height: NotchcastTheme.Pill.glyph)
            .accessibilityHidden(true)
    }
}

/// The spinner a state shows while it knows nothing better: the message HUD's own.
struct IslandSpinner: View {
    var body: some View {
        SymbolImage(name: "progress.indicator", size: NotchcastTheme.Pill.glyph)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
            .foregroundStyle(NotchcastTheme.Colors.primary)
            .frame(width: NotchcastTheme.Pill.glyph, height: NotchcastTheme.Pill.glyph)
            .accessibilityHidden(true)
    }
}

/// A state's value, in the row's trailing type with still digits; a percent keeps the volume HUD's readout slot.
struct IslandValueView: View {
    let value: IslandActivity.Value

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
        .font(NotchcastTheme.Typography.activityValue)
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

/// The album cover at the row icon's size, or a quiet note while the player gave none.
struct IslandArtwork: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                SymbolImage(name: "music.note", size: NotchcastTheme.Pill.glyph)
                    .foregroundStyle(NotchcastTheme.Colors.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NotchcastTheme.Colors.tile)
            }
        }
        .frame(width: NotchcastTheme.Pill.artwork, height: NotchcastTheme.Pill.artwork)
        .clipShape(RoundedRectangle(cornerRadius: NotchcastTheme.Corners.artwork, style: .continuous))
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
    @State private var high = false

    private var animates: Bool { moving && !reduceMotion }

    var body: some View {
        HStack(alignment: .center, spacing: NotchcastTheme.MusicBars.gap) {
            ForEach(0..<NotchcastTheme.MusicBars.count, id: \.self) { index in
                Capsule()
                    .fill(NotchcastTheme.Colors.primary)
                    .frame(width: NotchcastTheme.MusicBars.width, height: NotchcastTheme.MusicBars.height)
                    .scaleEffect(y: animates ? (high ? 1 : NotchcastTheme.MusicBars.lowestLevel)
                                 : NotchcastTheme.MusicBars.restingLevel)
                    .animation(animates ? .easeInOut(duration: NotchcastTheme.MusicBars.cycle)
                        .delay(NotchcastTheme.MusicBars.delays[index]).repeatForever(autoreverses: true) : nil,
                               value: high)
            }
        }
        .frame(height: NotchcastTheme.MusicBars.height)
        .onAppear { high = true }
        .accessibilityHidden(true)
    }
}

/// A transient message: the HUD pill's glyph and line, or either part for a notch wing. Only danger carries colour.
struct IslandMessageLine: View {
    enum Part { case glyph, text, row }
    let message: IslandMessage
    var part: Part = .row
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

    /// A short message sits in the notch's wings, glyph left and text right, so the band stays one row; only text
    /// past the title limit takes the row under the camera.
    static func fitsWings(_ message: IslandMessage) -> Bool {
        let font = NSFont.preferredFont(forTextStyle: .callout)
        let width = (message.text as NSString).size(withAttributes: [.font: font]).width
        return width <= NotchcastTheme.Pill.textLimit
    }

    private var content: some View {
        HStack(spacing: NotchcastTheme.Pill.artworkGap) {
            if part != .text {
                if hovered, message.onCancel != nil {
                    IslandGlyph(name: "xmark")
                } else if message.isProgress {
                    IslandSpinner()
                } else {
                    IslandGlyph(name: message.tone == .success ? "checkmark.circle"
                                : (message.tone == .danger ? "exclamationmark.circle" : "info.circle"),
                                tone: message.tone == .danger ? .danger : .plain)
                }
            }
            if part != .glyph { IslandWord(text: message.text) }
        }
        .frame(maxWidth: Theme.Size.hudMaxWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// An activity as a row: glyph, word, value; or any part of it, for a notch wing.
struct IslandActivityLine: View {
    enum Part { case glyph, value, row }
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
            }
            if part != .glyph, let value = activity.value { IslandValueView(value: value) }
        }
        .accessibilityElement(children: .combine)
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

/// A song as a row: cover, title over artist, bars; or any part of it, for a notch wing.
struct IslandMusicLine: View {
    enum Part { case artwork, bars, row }
    let music: IslandClosedState.Music
    var part: Part = .row

    var body: some View {
        HStack(spacing: NotchcastTheme.Pill.artworkGap) {
            if part != .bars { IslandArtwork(image: music.artwork) }
            if part == .row { IslandTrackText(title: music.title, artist: music.artist) }
            if part != .artwork {
                IslandLevelBars(moving: music.isPlaying)
                    .padding(.leading, part == .row ? NotchcastTheme.Pill.gap - NotchcastTheme.Pill.artworkGap : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(music.isPlaying ? music.title : String(localized: "Paused"))
        .accessibilityValue(music.artist)
    }
}
