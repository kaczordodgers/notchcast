#if DEBUG
import AppKit
import SwiftUI

extension GalleryPages {
    static let closedIslandStates = [
        "idle", "timer", "transfer", "status", "volume", "brightness", "airpods", "low-battery", "wifi", "tailscale",
        "low-disk", "meeting-reminder", "dictation", "walk", "message", "danger-message",
        "music", "music-paused", "recording", "count", "step", "speed", "toggle", "level", "spinner", "calibration",
        "two-at-once", "timer-end", "long-message",
        "agents", "camera", "mac-update", "several-items", "transcribing", "two-activities",
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
            let opening = ["start": 0.0, "middle": NotchcastTheme.Opening.middle]
                .sorted { $0.value < $1.value }.map { frame, progress in
                    islandPage(core, name: "island-opening-\(frame)-\(suffix)", display: display, notch: notch,
                               state: "music", open: false, opening: progress)
                }
            let ends = [InterfaceSize.larger, .large, .standard].map { size in
                launcherEnd(core, display: display, notch: notch, size: size,
                            suffix: size == .standard ? suffix : "\(size.rawValue)-\(suffix)")
            }
            let opened = ["home-empty", "home-entries", "day-calendar", "day-no-access"].map { state in
                islandPage(core, name: "island-open-\(state)-\(suffix)",
                           display: display, notch: notch, state: state, open: true)
            }
            return closed + opening + ends + opened
        } + [visualizerLab()]
    }

    private static func visualizerLab() -> GalleryPage {
        GalleryPage(name: "island-visualizers", types: ["IslandVisualizerComparisonView", "IslandVisualizer"],
                    makeWindow: {
            let view = IslandVisualizerComparisonView().motionScope()
            return window(view, size: NSHostingView(rootView: view).fittingSize, dark: true)
        })
    }

    private static func launcherEnd(_ core: AppCore, display: CGRect, notch: CGRect?, size: InterfaceSize,
                                    suffix: String) -> GalleryPage {
        GalleryPage(name: "launcher-opening-end-\(suffix)", types: ["RootPaletteView", "LauncherList"], makeWindow: {
            core.settings.interfaceSize = size
            let panel = IslandPanel(screenFrame: display, hardwareNotch: notch)
            let launcher = launcherFrame(under: panel)
            panel.showOpening(into: launcher, progress: 1)
            let shape = (panel.contentView?.layer?.mask as? CAShapeLayer)?.path ?? CGMutablePath()
            let canvas = panel.frame
            let local = CGRect(x: launcher.minX - canvas.minX, y: canvas.maxY - launcher.maxY,
                               width: launcher.width, height: launcher.height)
            core.palette.prepare(mode: .launcher)
            core.palette.noteCommandHeld(false)
            core.palette.query = ""
            let flip = CGAffineTransform(translationX: 0, y: canvas.height).scaledBy(x: 1, y: -1)
            let view = ZStack(alignment: .topLeading) {
                Color.clear
                Path(shape).transform(flip).fill(NotchcastTheme.Colors.surface)
                RootPaletteView().paletteEnvironment(core)
                    .frame(width: local.width, height: local.height)
                    .offset(x: local.minX, y: local.minY)
            }
            return window(view.motionScope(), size: canvas.size, dark: true)
        }, settle: .milliseconds(500), finish: { core.settings.interfaceSize = .standard })
    }

    private static func islandPage(
        _ core: AppCore, name: String, display: CGRect, notch: CGRect?, state: String, open: Bool,
        opening: CGFloat? = nil, interfaceSize: InterfaceSize = .standard
    ) -> GalleryPage {
        core.settings.interfaceSize = interfaceSize
        let canvas = IslandPanel.canvasHeight(notch)
        let canvasWidth = NotchcastTheme.Launcher.canvasWidth
        core.settings.interfaceSize = .standard
        return GalleryPage(name: name, types: ["IslandPanel", "IslandSurfaceView", "IslandClosedView",
                                              "IslandContentView", "IslandHeaderView"]
                    + (state == "day-calendar" ? ["ScheduleList"] : (open ? ["IslandHomeView"] : [])),
                    hardwareNotch: notch.map {
                        CGRect(x: $0.minX - (display.midX - canvasWidth / 2),
                               y: canvas - $0.height, width: $0.width, height: $0.height)
                    }, silhouette: { window in
                        (window.contentView?.layer?.mask as? CAShapeLayer)?.path ?? CGMutablePath()
                    }, makeWindow: {
            core.settings.interfaceSize = interfaceSize
            for activity in IslandActivityCenter.shared.activities { IslandActivityCenter.shared.finish(activity.id) }
            let panel = IslandPanel(screenFrame: display, hardwareNotch: notch)
            let island = IslandController()
            let pages = IslandPagesCoordinator(core: core, island: island)
            let header = IslandHeaderView(cameraWidth: notch?.width ?? 0, height: panel.headerHeight,
                                          shownPage: state.hasPrefix("day-") ? .day : .home)
                .environment(island).environment(pages)
            if state == "home-entries" {
                NotchcastPreferences.shared.set(.islandLiveActivities, true)
                IslandActivityCenter.shared.begin(IslandActivity(kind: .timer, title: "Tea timer",
                                                                 endDate: Date().addingTimeInterval(300)))
                IslandActivityCenter.shared.begin(IslandActivity(kind: .status, title: "Sample export complete"))
            }
            let content: AnyView
            if state == "day-calendar" {
                let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
                let events = ["Design review", "Project planning"].enumerated().map { index, title in
                    MeetingEvent(id: "sample-\(index)", title: title,
                                 start: Calendar.current.date(byAdding: .day, value: index, to: now)!,
                                 end: Calendar.current.date(byAdding: .day, value: index, to: now)!.addingTimeInterval(1800),
                                 isAllDay: false, isDeclined: false, calendarID: "sample",
                                 calendarName: "Sample calendar", calendarColor: .init(red: 0.4, green: 0.6, blue: 1),
                                 calendarItemID: "sample-\(index)", link: nil)
                }
                content = AnyView(ScheduleList(results: events, selectedID: events.first?.id, now: now,
                                               scroll: ScrollIntent(kind: .top), onActivate: { _ in }, onActions: { _ in })
                    .frame(height: 200))
            } else if state == "day-no-access" {
                content = AnyView(pages.noAccessContent())
            } else { content = AnyView(IslandHomeView()) }
            panel.setContent(open: AnyView(content.paletteEnvironment(core)), closed: closedFixture(state),
                             header: AnyView(header.paletteEnvironment(core)))
            panel.setOpen(open, animated: false)
            return panel
        }, prepare: { window in
            guard let panel = window as? IslandPanel else { return }
            panel.setOpen(open, animated: false)
            if let opening { panel.showOpening(into: launcherFrame(under: panel), progress: opening) }
        }, finish: { core.settings.interfaceSize = .standard })
    }

    /// Where the expanded launcher sits: centred on the island, its top under the notch or level with the pill.
    private static func launcherFrame(under panel: IslandPanel) -> CGRect {
        let body = panel.closedBodyFrame
        let size = NotchcastTheme.Launcher.size
        let top = panel.hardwareNotch?.minY ?? body.maxY
        return CGRect(x: body.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }

    /// Every fixture goes through the controller's own ranking, the way a live island builds its closed state.
    private static func closedFixture(_ state: String) -> IslandClosedState {
        let now = Date()
        let track = IslandTrack(title: "Teardrop", artist: "Massive Attack", artwork: sampleArtwork,
                                isPlaying: state != "music-paused")
        // 299 s so the frozen gallery frame reads 4:59, the same in both lanes.
        let tea = IslandActivity(kind: .timer, title: "Tea timer", endDate: now.addingTimeInterval(299))
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
        case "walk":
            shown.message = message(String(localized: "Daily walking goal reached", table: "Notchcast"),
                                    symbol: "figure.walk")
        case "message": shown.message = message("Nothing to Import")
        case "danger-message": shown.message = message("Couldn't read the text", .danger)
        case "music", "music-paused": shown.track = track
        case "recording":
            shown.activities = [activity(String(localized: "Recording", table: "Notchcast"), symbol: "record.circle",
                                         value: .elapsed(since: now - 83))]
        case "count": shown.activities = [activity("Copying files", symbol: "doc.on.doc", value: .count(3, of: 12))]
        case "agents":
            shown.activities = [activity("Agents waiting", symbol: "person.2", value: .count(2, of: 4))]
        case "camera": shown.activities = [activity("Camera", symbol: "video", value: .toggle(true))]
        case "mac-update":
            shown.activities = [activity("macOS update", symbol: "arrow.triangle.2.circlepath", value: .step(3, of: 7))]
        case "several-items":
            shown.activities = [IslandActivity(kind: .transfer, title: "Sample downloads", value: .count(2, of: 5))]
        case "transcribing":
            shown.activities = [activity("Transcribing", symbol: "text.quote", value: .spinner)]
        case "two-activities":
            shown.activities = [tea, IslandActivity(kind: .transfer, title: "Photos backup", progress: 0.64)]
        case "step": shown.activities = [activity("Installing update", symbol: "shippingbox", value: .step(2, of: 5))]
        case "speed":
            shown.activities = [activity(String(localized: "Downloading", table: "Notchcast"),
                                         symbol: "arrow.down.circle",
                                         value: .live(24.6, .megabitsPerSecond))]
        case "toggle":
            shown.activities = [activity(String(localized: "Keep Awake", table: "Notchcast"), symbol: "cup.and.saucer",
                                         value: .toggle(true))]
        case "level": shown.activities = [activity("Microphone", symbol: "mic", value: .level(0.6))]
        case "spinner": shown.activities = [activity("Syncing", symbol: "arrow.triangle.2.circlepath", value: .spinner)]
        case "calibration":
            shown.activities = [activity("Battery calibration", symbol: "battery.75percent",
                                         value: .pair(.percent(0.8), .step(2, of: 4)))]
        case "two-at-once": shown = (nil, [tea], track)
        case "timer-end":
            return IslandClosedState(main: .card(IslandCard(kind: .timerEnd, title: "Tea timer", action: {})))
        case "long-message":
            shown.message = message("Couldn't paste some dictation into the app",
                                    detail: "The text is on the clipboard instead")
        default: break
        }
        return IslandController.closedState(message: shown.message, activities: shown.activities, track: shown.track)
    }

    /// The shared sample cover: a flat #2F3E46 square with a centred #F4A261 circle half its width.
    private static let sampleArtwork = NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
        NSColor(srgbRed: 0x2F / 255, green: 0x3E / 255, blue: 0x46 / 255, alpha: 1).setFill()
        rect.fill()
        NSColor(srgbRed: 0xF4 / 255, green: 0xA2 / 255, blue: 0x61 / 255, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: rect.width / 4, dy: rect.height / 4)).fill()
        return true
    }
}
#endif
