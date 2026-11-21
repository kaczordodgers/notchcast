// notchcast-hosted-only
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/BarButton.swift
// notchcast-sources: Tinycast/DesignSystem/SymbolImage.swift Tinycast/DesignSystem/Tooltip.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchMenuInk.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageDeck.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandCardSlots.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageSwipe.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/UI/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/DictationIslandSession.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/DictationIslandNotice.swift
import AppKit
import SwiftUI

// Stand-ins for the menu icon types in PopoverMenu.swift, which drags in the whole palette.
enum PopoverMenuIcon: Equatable {
    case blank, symbol(String), asset(String), file(String), thumbnail(id: String, data: Data)
}
struct MenuFileIcon: View { let path: String; var body: some View { EmptyView() } }
struct MenuThumbnail: View { let id: String; let data: Data; var body: some View { EmptyView() } }

/// #975's acceptance set: the open island's pages in both forms, Black and Frosted, to PNGs at 2x.
/// `NC_AUDIT_RENDERS` names the folder, else the audit harness's own, which CI uploads.
@MainActor
@main
struct IslandPagesRenderTest {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    static let notchSize = CGSize(width: 185, height: 32)
    static let margin: CGFloat = 32

    static func main() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A run's own stale PNGs must not pass for this run's.
        for old in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where ["975-", "960-open-"].contains(where: old.lastPathComponent.hasPrefix) {
            try FileManager.default.removeItem(at: old)
        }
        var sizes: [String: CGSize] = [:]
        for frosted in [false, true] {
            for notch in [false, true] {
                let suffix = "\(notch ? "notch" : "island")-\(frosted ? "frosted" : "black")"
                var bitmaps: [String: NSBitmapImageRep] = [:]
                for (name, deck) in decks() {
                    (sizes[name], bitmaps[name]) = render("975-\(name)-\(suffix)", deck: deck, notch: notch,
                                                          frosted: frosted)
                }
                for (name, deck) in dictationDecks() {
                    _ = render("960-open-\(name)-\(suffix)", deck: deck, notch: notch, frosted: frosted)
                }
                checkTones(toned: bitmaps["3-home-tones"]!, plain: bitmaps["3-home-untoned"]!, frosted: frosted,
                           look: suffix)
            }
        }
        precondition(sizes["1-player"] != sizes["3-home"] && sizes["3-home"] != sizes["5-system"],
                     "pages size to their content: no fixed width or height (946-6)")
        precondition(sizes["5-home"]!.height > sizes["3-home"]!.height, "five lines stand taller than three")
        precondition(sizes["0-home"]!.height < sizes["3-home"]!.height, "a bare island's Home holds one line (#884)")
        precondition(sizes["agents-slots"]!.width == Theme.Size.panelWidth && sizes["agents-alone"]!.width
            == Theme.Size.panelWidth, "a page of cards keeps the launcher's width (#1128)")
        print("agents-slots \(sizes["agents-slots"]!), agents-alone \(sizes["agents-alone"]!)")
        print("PASS rendered island pages to \(folder.path)")
    }

    static func decks() -> [(String, IslandPageDeck)] {
        let player = IslandPlayerPage.page(IslandNowPlaying(
            title: "Paper Lanterns", artist: "Juno Vale", artwork: artwork(),
            time: IslandMediaTime(elapsed: 72, duration: 214, rate: 0, sampledAt: Date(timeIntervalSince1970: 0)),
            isPlaying: true))
        let agents = IslandPage(id: "agents", title: "Agents", symbol: "person.2", order: 0, badge: 2,
            line: IslandPageLine(symbol: "person.2", text: "2 agents need you", detail: "Release notes, Island pages"),
            blocks: [.row(IslandPageRow(id: "a", symbol: "questionmark.bubble", title: "Release notes",
                                        detail: "Asks which version to ship", trailing: "2 min")),
                     .row(IslandPageRow(id: "b", symbol: "hammer", title: "Island pages",
                                        detail: "Building", trailing: "14 min"))])
        var calm = agents
        calm.badge = 0
        calm.line = IslandPageLine(symbol: "person.2", text: "3 agents working", detail: "None waiting")
        let system = IslandPage(id: "system", title: "System", symbol: "cpu", order: 20,
            line: IslandPageLine(symbol: "cpu", text: "CPU 18 %", detail: "Memory 61 %"),
            blocks: [.meter(IslandPageMeter(label: "CPU", fraction: 0.18, value: "18 %")),
                     .meter(IslandPageMeter(label: "Memory", fraction: 0.61, value: "61 %")),
                     .meter(IslandPageMeter(label: "Disk", fraction: 0.42, value: "212 GB free"))])
        let day = IslandPage(id: "day", title: "Day", symbol: "sun.max", order: 30,
            line: IslandPageLine(symbol: "sun.max", text: "14° Partly cloudy", detail: "Stand-up at 10:30"),
            blocks: [.row(IslandPageRow(symbol: "calendar", title: "Stand-up", trailing: "10:30"))])
        let usage = IslandPage(id: "usage", title: "Usage", symbol: "gauge.with.dots.needle.33percent", order: 40,
            line: IslandPageLine(symbol: "gauge.with.dots.needle.33percent", text: "AI plan 64 % left"),
            blocks: [.meter(IslandPageMeter(label: "AI plan", fraction: 0.64, value: "64 % left"))])
        func deck(_ pages: [IslandPage], select: IslandPageDeck.Tab? = nil) -> IslandPageDeck {
            var deck = IslandPageDeck()
            for page in pages { deck.set(page, id: page.id) }
            if let select { deck.select(select) }
            return deck
        }
        func noticed(_ deck: IslandPageDeck) -> IslandPageDeck {
            var deck = deck
            deck.show(IslandNotice(id: "update", symbol: "arrow.down.circle", text: "Update ready"), tappable: true)
            return deck
        }
        func toned(_ page: IslandPage, _ tone: IslandTone?, _ text: String) -> IslandPage {
            var page = page
            page.line.text = text
            page.line.tone = tone
            return page
        }
        let (board, alone) = agentBoards()
        return [
            ("agents-slots", deck([board, player], select: .page(board.id))),
            ("agents-alone", deck([alone])),
            ("0-home", deck([])),
            ("1-player", deck([player])),
            ("1-player-full", deck([fullPlayer()])),
            ("1-player-full-paused-long", deck([fullPlayer(paused: true, long: true)])),
            ("1-player-notice", noticed(deck([player]))),
            ("3-home-notice", noticed(deck([calm, player, system]))),
            ("3-home", deck([calm, player, system])),
            ("3-home-tones", deck([calm, toned(system, .warning, "CPU 96 %"), toned(day, .critical, "Disk almost full")])),
            ("3-home-untoned", deck([calm, toned(system, nil, "CPU 96 %"), toned(day, nil, "Disk almost full")])),
            ("3-player", deck([calm, player, system], select: .page(IslandPlayerPage.id))),
            ("5-home", deck([agents, player, system, day, usage])),
            ("5-system", deck([agents, player, system, day, usage], select: .page("system"))),
        ]
    }

    /// #960: the dictation notice heads the open page, recording over Home, a failure over a page.
    static func dictationDecks() -> [(String, IslandPageDeck)] {
        var session = DictationIslandSession()
        session.begin(copies: false, at: 0)
        _ = session.hear(levels: [0.4], at: 7)
        let player = IslandPlayerPage.page(IslandNowPlaying(title: "Paper Lanterns", artist: "Juno Vale",
                                                            artwork: artwork(), time: nil, isPlaying: true))
        let system = IslandPage(id: "system", title: "System", symbol: "cpu", order: 20,
            line: IslandPageLine(symbol: "cpu", text: "CPU 18 %", detail: "Memory 61 %"),
            blocks: [.meter(IslandPageMeter(label: "CPU", fraction: 0.18, value: "18 %"))])
        func deck(_ notice: IslandNotice, select: IslandPageDeck.Tab?) -> IslandPageDeck {
            var deck = IslandPageDeck()
            for page in [player, system] { deck.set(page, id: page.id) }
            if let select { deck.select(select) }
            deck.show(notice, tappable: false)
            return deck
        }
        return [("recording-home", deck(IslandNotice(dictation: session)!, select: nil)),
                ("failed-page", deck(IslandNotice(dictation: .failed), select: .page("system")))]
    }

    /// #1128's approved board (pill-slots, notch-slots), and one Mac alone with no feed.
    static func agentBoards() -> (IslandPage, IslandPage) {
        /// Drawn as Agents draws it: what is left, the tick where an even pace leaves the fill.
        func meter(_ label: String, _ used: Int, _ resets: String, tick gone: Double?, thick: Bool = false,
                   note: String? = nil) -> IslandCardMeter {
            IslandCardMeter(label: label, value: "\(100 - used)% left", trailing: resets,
                            fraction: Double(100 - used) / 100, tick: gone.map { 1 - $0 }, thick: thick,
                            warning: note != nil, note: note)
        }
        func spent(_ name: String, _ back: String, tag: IslandCardTag? = nil) -> IslandCard {
            IslandCard(title: name, tag: tag, hollow: true,
                       body: .notice(symbol: "hourglass", headline: "Back in \(back)", detail: "Weekly limit used up"))
        }
        let credit = IslandCardTag(symbol: "arrow.counterclockwise", text: "1 reset credit")
        let c1 = IslandCard(title: "C1", tag: credit, body: .meters([
            meter("Session", 22, "in 2 h 10 min", tick: 0.57), meter("Weekly", 15, "in 5 d 14 h", tick: 0.2, thick: true),
            meter("Weekly · Fable", 12, "in 5 d 14 h", tick: 0.2),
            IslandCardMeter(label: "Extra usage", value: "83% left", trailing: "$166 of $200", fraction: 0.83)]))
        let c2 = IslandCard(title: "C2", body: .meters([
            meter("Session", 40, "in 2 h 30 min", tick: 0.5), meter("Weekly", 70, "in 8 h 24 min", tick: 0.95, thick: true),
            meter("Weekly · Fable", 31, "in 8 h 24 min", tick: 0.95)]))
        let c4 = IslandCard(title: "C4", body: .meters([
            meter("Session", 5, "in 4 h 5 min", tick: 0.18),
            meter("Weekly", 45, "in 5 d 14 h", tick: 0.2, thick: true, note: "Runs out in 1 d 17 h"),
            meter("Weekly · Fable", 12, "in 5 d 14 h", tick: 0.2)]))
        let c6 = IslandCard(title: "C6", body: .meters([
            meter("Session", 15, "in 45 min", tick: 0.85), meter("Weekly", 40, "in 3 d 17 h", tick: 0.47, thick: true),
            meter("Weekly · Fable", 20, "in 3 d 17 h", tick: 0.47)]))
        var stale = c6
        stale.dimmed = true
        stale.caption = "Couldn’t refresh · updated 25 min ago"
        let fable = IslandCardTag(symbol: "arrow.counterclockwise", text: "1 Fable reset credit")
        let other = IslandCardGroup(title: "Other", cards: [
            spent("Codex", "2 d 19 h"),
            IslandCard(title: "Grok", body: .meters([meter("Weekly", 29, "in 2 d 15 h", tick: 0.62, thick: true)])),
            IslandCard(title: "OpenCode", body: .meters([meter("Weekly", 20, "in 4 d 9 h", tick: 0.37, thick: true),
                                                         meter("Monthly", 50, "in 12 d 7 h", tick: 0.59)])),
            spent("Antigravity", "1 d 21 h")])
        let line = IslandPageLine(symbol: "gauge.with.needle", text: "C4 · Weekly runs out in 1 d 17 h")
        let board = IslandPage(id: "agents", title: "Agents", symbol: "gauge.with.needle", order: 0, line: line,
            blocks: [.columns([IslandCardGroup(title: "MBA", cards: [c1, c2]),
                               IslandCardGroup(title: "MBP", cards: [c4, spent("C3", "2 d 3 h"),
                                                                     spent("C5", "4 d 16 h", tag: fable)]),
                               IslandCardGroup(title: "VPS", cards: [stale])]),
                     .cards(other)])
        let alone = IslandPage(id: "agents", title: "Agents", symbol: "gauge.with.needle", order: 0, line: line,
            blocks: [.columns([IslandCardGroup(title: "MBA", cards: [c1]), IslandCardGroup(title: "", cards: [c2]),
                               IslandCardGroup(title: "", cards: [spent("Codex", "2 d 19 h"),
                                   IslandCard(title: "C7", hollow: true, body: .notice(
                                       symbol: "person.crop.circle.badge.exclamationmark",
                                       headline: "Sign in to Claude Code", detail: nil))])]),
                     .row(IslandPageRow(symbol: "info.circle", title: "This Mac only: no feed found."))])
        return (board, alone)
    }

    /// A gradient cover, so the artwork slot shows a real image without a fixture file.
    /// #850 part B: like, seek, volume and Up Next beside the player.
    static func fullPlayer(paused: Bool = false, long: Bool = false) -> IslandPage {
        var playing = IslandNowPlaying(
            title: long ? "Everything Everywhere at Once (Extended Midnight Version)" : "Paper Lanterns",
            artist: long ? "Juno Vale, The Paper Lanterns Orchestra" : "Juno Vale", artwork: artwork(),
            time: IslandMediaTime(elapsed: 72, duration: 214, rate: 0, sampledAt: Date(timeIntervalSince1970: 0)),
            isPlaying: !paused)
        playing.liked = !paused
        playing.volume = 0.6
        playing.seekable = true
        playing.upNext = [IslandQueuedSong(id: "1", title: "Glass Harbour", artist: "Juno Vale"),
                          IslandQueuedSong(id: "2", title: "Low Tide", artist: "Mira North"),
                          IslandQueuedSong(id: "3", title: "Night Ferry (Live at the Old Pier, 2019)",
                                           artist: "The Paper Lanterns Orchestra")]
        return IslandPlayerPage.page(playing)
    }

    static func artwork() -> Data? {
        let image = NSImage(size: CGSize(width: 128, height: 128), flipped: false) { rect in
            NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: rect, angle: 45)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// A dropped `tone:` hop (line, label, artwork) greys the glyph; hue survives 1x antialiasing.
    static func checkTones(toned: NSBitmapImageRep, plain: NSBitmapImageRep, frosted: Bool, look: String) {
        precondition(toned.pixelsWide == plain.pixelsWide && toned.pixelsHigh == plain.pixelsHigh,
                     "a tone never resizes the Home line (\(look))")
        func hue(_ color: NSColor?) -> (hue: CGFloat, chroma: CGFloat) {
            guard let color = color?.usingColorSpace(.sRGB) else { return (0, 0) }
            let rgb = [color.redComponent, color.greenComponent, color.blueComponent]
            return (color.hueComponent, rgb.max()! - rgb.min()!)
        }
        func tone(_ ink: (hue: CGFloat, chroma: CGFloat), among inks: [(IslandTone, CGFloat)]) -> IslandTone? {
            guard ink.chroma > 0.15 else { return nil }
            return inks.first { min(abs($0.1 - ink.hue), 1 - abs($0.1 - ink.hue)) < 0.03 }?.0
        }
        let inks = IslandTone.allCases.map { tone in
            let swatch = Rectangle().fill(tone.color).environment(\.islandFrosted, frosted)
            return (tone, hue(snapshot(swatch.environment(\.colorScheme, .dark), size: CGSize(width: 8, height: 8))
                .colorAt(x: 4, y: 4)).hue)
        }
        var hits: [IslandTone: Int] = [:]
        for y in 0..<toned.pixelsHigh {
            for x in 0..<toned.pixelsWide {
                let (before, after) = (hue(plain.colorAt(x: x, y: y)), hue(toned.colorAt(x: x, y: y)))
                if let stray = tone(before, among: inks) {
                    preconditionFailure("an untoned Home line draws no \(stray) ink (\(look))")
                }
                guard let ink = tone(after, among: inks) else { continue }
                hits[ink, default: 0] += 1
                precondition(before.chroma < 0.08, "nil inks the Home glyph grey as before, where \(ink) inks it (\(look))")
            }
        }
        for tone in IslandTone.allCases {
            precondition(hits[tone, default: 0] >= 20, "a \(tone) Home line inks its glyph (\(look)): \(hits)")
        }
    }

    static func snapshot(_ view: some View, size: CGSize) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    /// The island hanging from the screen's top edge, sized as `IslandPageHost` sizes it, below a notch or not.
    static func render(_ name: String, deck: IslandPageDeck, notch: Bool,
                       frosted: Bool) -> (CGSize, NSBitmapImageRep) {
        let pages = IslandPagesView(deck: deck, select: { _ in }, act: { _, _ in })
            .environment(\.metrics, InterfaceMetrics.standard)
            .environment(\.islandFrosted, frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark)
        let fit = NSHostingView(rootView: pages).fittingSize
        let size = IslandPageDeck.outline(content: fit, rest: NotchTheme.Size.islandRest,
                                          notch: notch ? notchSize.width : nil, radius: Theme.Radius.panel,
                                          maxHeight: 2000)
        let top = notch ? notchSize.height : 0
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Theme.Radius.panel,
                                           bottomTrailingRadius: Theme.Radius.panel, style: .continuous)
        let island = ZStack(alignment: .top) {
            shape.fill(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface)
            if frosted { shape.strokeBorder(NotchTheme.Colors.islandEdge, lineWidth: 1) }
            if notch { Rectangle().fill(Color.black).frame(width: notchSize.width, height: notchSize.height) }
            pages.frame(width: size.width, height: size.height).offset(y: top)
        }
        .frame(width: size.width, height: top + size.height)
        let canvas = CGSize(width: size.width + 2 * margin, height: top + size.height + margin)
        let view = island
            .frame(width: canvas.width, height: canvas.height, alignment: .top)
            .background(frosted ? Color.white : Color(white: 0.18))
            .environment(\.colorScheme, .dark)
        let bitmap = snapshot(view, size: canvas)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { preconditionFailure("\(name) PNG") }
        do {
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            preconditionFailure("\(name): \(error)")
        }
        return (size, bitmap)
    }
}
