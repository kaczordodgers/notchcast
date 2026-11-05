#if DEBUG
import AppKit
import SwiftUI

extension GalleryPages {
    /// The 16 closed states on main, the music and value pages, two at once, the cards and the opening's frames.
    static let closedIslandStates = [
        "idle", "timer", "transfer", "status", "volume", "brightness", "airpods", "low-battery", "wifi", "tailscale",
        "low-disk", "meeting-reminder", "dictation", "walk", "message", "danger-message",
        "music", "music-paused", "recording", "count", "step", "speed", "toggle", "level", "spinner", "calibration",
        "two-at-once", "music-and-timer", "timer-end", "long-message",
    ]

    static func island(_ core: AppCore) -> [GalleryPage] {
        [true, false].flatMap { mba in
            let display = CGRect(x: 0, y: 0, width: mba ? 1470 : 1920, height: mba ? 956 : 1080)
            let notch = mba ? CGRect(x: display.midX - 92, y: display.maxY - 32, width: 184, height: 32) : nil
            let suffix = mba ? "mba" : "ext"
            let closed = closedIslandStates.map { state in
                islandPage(core, name: "island-closed-\(state)-\(suffix)",
                           display: display, notch: notch, state: state, open: false)
            }
            let opening = ["start": 0.0, "middle": NotchcastTheme.Opening.middle, "end": 1.0]
                .sorted { $0.value < $1.value }.map { frame, progress in
                    islandPage(core, name: "island-opening-\(frame)-\(suffix)", display: display, notch: notch,
                               state: "music", open: false, opening: progress)
                }
            let opened = ["home-empty", "home-entries", "day-calendar"].map { state in
                islandPage(core, name: "island-open-\(state)-\(suffix)",
                           display: display, notch: notch, state: state, open: true)
            }
            return closed + opening + opened
        } + [visualizerLab()]
    }

    private static func visualizerLab() -> GalleryPage {
        let size = CGSize(width: 2 * NotchcastTheme.Visualizer.labTile.width + Theme.Spacing.lg + 2 * Theme.Spacing.xl,
                          height: NotchcastTheme.Visualizer.labTile.height * 2 + 2 * Theme.Spacing.xl)
        return GalleryPage(name: "island-visualizer-lab", types: ["IslandVisualizerLabView", "IslandVisualizer"],
                           makeWindow: { window(IslandVisualizerLabView(), size: size, dark: true) })
    }

    private static func islandPage(
        _ core: AppCore, name: String, display: CGRect, notch: CGRect?, state: String, open: Bool,
        opening: CGFloat? = nil
    ) -> GalleryPage {
        let canvas = IslandPanel.canvasHeight(notch)
        return GalleryPage(name: name, types: ["IslandPanel", "IslandSurfaceView", "IslandClosedView",
                                              "IslandContentView", "IslandHeaderView"]
                    + (state == "day-calendar" ? ["ScheduleList"] : (open ? ["IslandHomeView"] : [])),
                    hardwareNotch: notch.map {
                        CGRect(x: $0.minX - (display.midX - NotchcastTheme.openMinimumWidth / 2),
                               y: canvas - $0.height, width: $0.width, height: $0.height)
                    }, silhouette: { window in
                        (window.contentView?.layer?.mask as? CAShapeLayer)?.path ?? CGMutablePath()
                    }, makeWindow: {
            for activity in IslandActivityCenter.shared.activities { IslandActivityCenter.shared.finish(activity.id) }
            let panel = IslandPanel(screenFrame: display, hardwareNotch: notch)
            let island = IslandController()
            let pages = IslandPagesCoordinator(core: core, island: island)
            let header = IslandHeaderView(cameraWidth: notch?.width ?? 0, height: panel.headerHeight)
                .environment(island).environment(pages)
            if state == "home-entries" {
                NotchcastPreferences.shared.set(.islandLiveActivities, true)
                IslandActivityCenter.shared.begin(IslandActivity(kind: .timer, title: "Tea timer",
                                                                 endDate: Date().addingTimeInterval(300)))
                IslandActivityCenter.shared.begin(IslandActivity(kind: .status, title: "Sample export complete"))
            }
            let content: AnyView
            if state == "day-calendar" {
                let now = Date()
                let events = ["Design review", "Project planning"].enumerated().map { index, title in
                    MeetingEvent(id: "sample-\(index)", title: title,
                                 start: now.addingTimeInterval(Double(index + 1) * 3600),
                                 end: now.addingTimeInterval(Double(index + 1) * 3600 + 1800),
                                 isAllDay: false, isDeclined: false, calendarID: "sample",
                                 calendarName: "Sample calendar", calendarColor: .init(red: 0.4, green: 0.6, blue: 1),
                                 calendarItemID: "sample-\(index)", link: nil)
                }
                content = AnyView(ScheduleList(results: events, selectedID: events.first?.id, now: now,
                                               scroll: ScrollIntent(kind: .top), onActivate: { _ in }, onActions: { _ in })
                    .frame(height: 200))
            } else { content = AnyView(IslandHomeView()) }
            panel.setContent(open: AnyView(content.paletteEnvironment(core)), closed: closedFixture(state),
                             header: AnyView(header.paletteEnvironment(core)))
            panel.setOpen(open, animated: false)
            return panel
        }, prepare: { window in
            guard let panel = window as? IslandPanel else { return }
            panel.setOpen(open, animated: false)
            if let opening { panel.showOpening(into: launcherFrame(under: panel), progress: opening) }
        })
    }

    /// Where the expanded launcher sits: centred under the closed body, the launcher gap below it.
    private static func launcherFrame(under panel: IslandPanel) -> CGRect {
        let body = panel.closedBodyFrame
        let size = NotchcastTheme.Launcher.size
        return CGRect(x: body.midX - size.width / 2, y: body.minY - NotchcastTheme.Launcher.gap - size.height,
                      width: size.width, height: size.height)
    }

    /// Every fixture goes through the controller's own ranking, the way a live island builds its closed state.
    private static func closedFixture(_ state: String) -> IslandClosedState {
        let now = Date()
        let track = IslandTrack(title: "Night drive", artist: "Mara Lind", artwork: sampleArtwork,
                                isPlaying: state != "music-paused")
        let tea = IslandActivity(kind: .timer, title: "Tea timer", endDate: now.addingTimeInterval(300))
        func message(_ text: String, _ tone: IslandMessage.Tone = .neutral, symbol: String? = nil,
                     detail: String? = nil, progress: Bool = false) -> IslandMessage {
            IslandMessage(id: UUID(), tone: tone, text: text, isProgress: progress, onCancel: nil,
                          detail: detail, symbol: symbol)
        }
        func activity(_ title: String, symbol: String, value: IslandValue) -> IslandActivity {
            IslandActivity(kind: .status, title: title, symbol: symbol, value: value)
        }
        var shown: (message: IslandMessage?, activities: [IslandActivity], track: IslandTrack?) = (nil, [], nil)
        switch state {
        case "timer": shown.activities = [tea]
        case "transfer": shown.activities = [IslandActivity(kind: .transfer, title: "Photos backup", progress: 0.64)]
        case "status": shown.message = message("Exported 24 photos", .success)
        case "volume", "brightness":
            let center = IslandActivityCenter()
            let presenter = SystemLevelIslandPresenter(center: center)
            presenter.present(LevelNotice(kind: state == "volume" ? .volume : .brightness,
                                          level: state == "volume" ? 0.40 : 0.75))
            shown.activities = center.ranked
            presenter.present(nil)
        case "airpods": shown.message = message("AirPods: Connected", symbol: "headphones")
        case "low-battery": shown.message = message("Low battery: 10%", .warning, symbol: "battery.25percent")
        case "wifi": shown.message = message("Wi-Fi: Connected", symbol: "wifi")
        case "tailscale": shown.message = message("Tailscale: Connected", symbol: "network")
        case "low-disk": shown.message = message("Low disk space: 12 GB", .warning, symbol: "internaldrive")
        case "meeting-reminder":
            shown.activities = [IslandActivity(
                kind: .status, title: "Design review", symbol: "calendar",
                meeting: .init(start: now.addingTimeInterval(300), tint: [0.4, 0.6, 1],
                               link: URL(string: "https://meet.google.com/abc-defg-hij")))]
        case "dictation": shown.message = message("Dictation listening", progress: true)
        case "walk": shown.message = message("Daily walking goal reached", symbol: "figure.walk")
        case "message": shown.message = message("Nothing to Import")
        case "danger-message": shown.message = message("Couldn’t read the text", .danger)
        case "music", "music-paused": shown.track = track
        case "recording":
            shown.activities = [activity("Recording", symbol: "record.circle", value: .elapsed(since: now - 83))]
        case "count": shown.activities = [activity("Copying files", symbol: "doc.on.doc", value: .count(3, of: 12))]
        case "step": shown.activities = [activity("Installing update", symbol: "shippingbox", value: .step(2, of: 5))]
        case "speed":
            shown.activities = [activity("Downloading", symbol: "arrow.down.circle",
                                         value: .live(24.6, .megabitsPerSecond))]
        case "toggle": shown.activities = [activity("Keep Awake", symbol: "cup.and.saucer", value: .toggle(true))]
        case "level": shown.activities = [activity("Microphone", symbol: "mic", value: .level(0.6))]
        case "spinner": shown.activities = [activity("Syncing", symbol: "arrow.triangle.2.circlepath", value: .spinner)]
        case "calibration":
            shown.activities = [activity("Battery calibration", symbol: "battery.75percent",
                                         value: .pair(.percent(0.8), .step(2, of: 4)))]
        case "two-at-once": shown = (message("AirPods: Connected", symbol: "headphones"), [], track)
        case "music-and-timer": shown = (nil, [tea], track)
        case "timer-end":
            return IslandClosedState(main: .card(IslandCard(kind: .timerEnd, title: "Tea timer", action: {})))
        case "long-message":
            shown.message = message("Couldn’t paste some dictation into this app",
                                    detail: "The text is on the clipboard instead")
        default: break
        }
        return IslandController.closedState(message: shown.message, activities: shown.activities, track: shown.track)
    }

    /// A plausible cover for "Night drive": a road under a low moon, flat colours, the one coloured thing on screen.
    private static let sampleArtwork = NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
        NSColor(srgbRed: 0.11, green: 0.13, blue: 0.19, alpha: 1).setFill()
        rect.fill()
        NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: 64, height: 26).fill()
        let road = NSBezierPath()
        road.move(to: CGPoint(x: 6, y: 0))
        road.line(to: CGPoint(x: 31, y: 26))
        road.line(to: CGPoint(x: 33, y: 26))
        road.line(to: CGPoint(x: 58, y: 0))
        road.close()
        NSColor(srgbRed: 0.93, green: 0.62, blue: 0.28, alpha: 1).setFill()
        road.fill()
        NSColor(srgbRed: 0.96, green: 0.93, blue: 0.86, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 36, y: 36, width: 12, height: 12)).fill()
        return true
    }
}
#endif
