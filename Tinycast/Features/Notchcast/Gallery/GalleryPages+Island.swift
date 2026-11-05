#if DEBUG
import AppKit
import SwiftUI

extension GalleryPages {
    static func island(_ core: AppCore) -> [GalleryPage] {
        [true, false].flatMap { mba in
            let display = CGRect(x: 0, y: 0, width: mba ? 1470 : 1920, height: mba ? 956 : 1080)
            let notch = mba ? CGRect(x: display.midX - 92, y: display.maxY - 32, width: 184, height: 32) : nil
            let suffix = mba ? "mba" : "ext"
            let closed = ["idle", "timer", "transfer", "status", "volume", "brightness", "airpods",
                          "low-battery", "wifi", "tailscale", "low-disk", "meeting-reminder",
                          "dictation", "walk", "message", "danger-message",
                          "music", "music-paused", "recording", "several-items", "mac-update", "speed-test",
                          "camera", "transcribing", "agents", "two-at-once", "two-activities", "long-message",
                          "timer-end", "spinner"].map { state in
                islandPage(core, name: "island-closed-\(state)-\(suffix)",
                           display: display, notch: notch, state: state, open: false)
            }
            let opened = ["home-empty", "home-entries", "day-calendar"].map { state in
                islandPage(core, name: "island-open-\(state)-\(suffix)",
                           display: display, notch: notch, state: state, open: true)
            }
            let opening = ["start", "mid"].map { frame in
                islandPage(core, name: "launcher-opening-\(frame)-\(suffix)",
                           display: display, notch: notch, state: "opening-\(frame)", open: false)
            }
            return closed + opened + opening + [launcherEnd(core, display: display, notch: notch, suffix: suffix)]
        } + [visualizers()]
    }

    /// The sample song for the music states: a generated cover, so the picture needs no player.
    static let sampleMusic = IslandClosedState.Music(title: "Teardrop", artist: "Massive Attack",
                                                     artwork: sampleArtwork(), isPlaying: true)

    /// The shared cover (SAME-DATA.md): a flat #2F3E46 square with a centred #F4A261 circle at half its width.
    private static func sampleArtwork() -> NSImage {
        let side = NotchcastTheme.Pill.artwork * 4
        return NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSColor(srgbRed: 0x2F / 255, green: 0x3E / 255, blue: 0x46 / 255, alpha: 1).setFill()
            rect.fill()
            NSColor(srgbRed: 0xF4 / 255, green: 0xA2 / 255, blue: 0x61 / 255, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: rect.width / 4, dy: rect.height / 4)).fill()
            return true
        }
    }

    /// The closed state a page shows: one activity per value type, the message states, the two-at-once pairs.
    static func closedState(_ state: String) -> IslandClosedState {
        let soon = Date().addingTimeInterval(300)
        let timer = IslandActivity(kind: .timer, title: "Tea timer", value: .timeLeft(soon))
        let transfer = IslandActivity(kind: .transfer, title: "Photos backup", value: .percent(0.64))
        switch state {
        case "timer-end":
            return IslandClosedState(primary: IslandActivity(kind: .timer, title: "Tea timer", value: .number("Done"),
                                                             action: "Stop"))
        case "spinner":
            return IslandClosedState(primary: IslandActivity(kind: .status, title: "Syncing", symbol: "arrow.triangle.2.circlepath",
                                                             value: .spinner))
        case "timer": return IslandClosedState(primary: timer)
        case "transfer": return IslandClosedState(primary: transfer)
        case "volume", "brightness":
            let center = IslandActivityCenter()
            let presenter = SystemLevelIslandPresenter(center: center)
            presenter.present(LevelNotice(kind: state == "volume" ? .volume : .brightness,
                                          level: state == "volume" ? 0.40 : 0.75))
            let activity = center.current
            presenter.present(nil)
            return IslandClosedState(primary: activity)
        case "meeting-reminder":
            return IslandClosedState(primary: IslandActivity(kind: .status, title: "Design review", symbol: "calendar",
                                                             value: .number("in 6 min"), action: "Join"))
        case "music": return IslandClosedState(music: sampleMusic)
        case "music-paused":
            var paused = sampleMusic
            paused.isPlaying = false
            return IslandClosedState(music: paused)
        case "recording":
            return IslandClosedState(primary: IslandActivity(
                kind: .status, title: "Screen recording", symbol: "record.circle",
                value: .elapsed(since: Date().addingTimeInterval(-83))))
        case "several-items":
            return IslandClosedState(primary: IslandActivity(kind: .transfer, title: "Sample downloads", value: .count(2, of: 5)))
        case "mac-update":
            return IslandClosedState(primary: IslandActivity(kind: .status, title: "macOS update",
                                                             symbol: "arrow.triangle.2.circlepath", value: .step(3, of: 7)))
        case "speed-test":
            return IslandClosedState(primary: IslandActivity(kind: .status, title: "Speed test", symbol: "speedometer",
                                                             value: .number("184 Mb/s")))
        case "camera":
            return IslandClosedState(primary: IslandActivity(kind: .status, title: "Camera", symbol: "video",
                                                             value: .onOff(true)))
        case "transcribing":
            return IslandClosedState(primary: IslandActivity(kind: .status, title: "Transcribing", symbol: "text.quote",
                                                             value: .spinner))
        case "agents":
            return IslandClosedState(primary: IslandActivity(kind: .status, title: "Agents waiting", symbol: "person.2",
                                                             value: .count(2, of: 4)))
        case "two-at-once": return IslandClosedState(primary: timer, music: sampleMusic)
        case "two-activities": return IslandClosedState(primary: timer, secondary: transfer)
        default: return IslandClosedState()
        }
    }

    private static func islandPage(
        _ core: AppCore, name: String, display: CGRect, notch: CGRect?, state: String, open: Bool
    ) -> GalleryPage {
        let closedTypes = ["IslandClosedView", "IslandActivityLine", "IslandMusicLine", "IslandGlyph", "IslandValueView",
                           "IslandWord", "IslandArtwork", "IslandTrackText", "IslandLevelBars", "IslandMessageLine",
                           "IslandActionButton"]
        return GalleryPage(name: name, types: ["IslandPanel", "IslandSurfaceView", "IslandContentView", "IslandHeaderView"]
                    + (state == "day-calendar" ? ["ScheduleList"] : (open ? ["IslandHomeView"] : closedTypes)),
                    hardwareNotch: notch.map {
                        CGRect(x: $0.minX - (display.midX - NotchcastTheme.openMinimumWidth / 2),
                               y: NotchcastTheme.maximumHeight, width: $0.width, height: $0.height)
                    }, silhouette: { window in
                        (window.contentView?.layer?.mask as? CAShapeLayer)?.path ?? CGMutablePath()
                    }, makeWindow: {
            for activity in IslandActivityCenter.shared.activities { IslandActivityCenter.shared.finish(activity.id) }
            if state == "home-entries" {
                NotchcastPreferences.shared.set(.islandLiveActivities, true)
                IslandActivityCenter.shared.begin(closedState("timer").primary!)
                IslandActivityCenter.shared.begin(IslandActivity(kind: .status, title: "Sample export complete"))
            }
            let panel = IslandPanel(screenFrame: display, hardwareNotch: notch)
            let island = IslandController()
            let pages = IslandPagesCoordinator(core: core, island: island)
            let header = IslandHeaderView(cameraWidth: notch?.width ?? 0, height: panel.headerHeight)
                .environment(island).environment(pages)
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
            panel.setContent(open: AnyView(content.paletteEnvironment(core)), closed: closedState(state),
                             header: AnyView(header.paletteEnvironment(core)))
            let messages = ["status": "Exported 24 photos", "airpods": "AirPods: Connected",
                            "low-battery": "Low battery: 10%", "wifi": "Wi-Fi: Connected",
                            "tailscale": "Tailscale: Connected", "low-disk": "Low disk space: 12 GB",
                            "dictation": "Dictation listening", "walk": "Daily walking goal reached.",
                            "message": "Nothing to Import", "danger-message": "Couldn't read the text",
                            "long-message": "Couldn't paste some dictation into the app"]
            if let text = messages[state] {
                let danger = ["low-battery", "low-disk", "danger-message"].contains(state)
                panel.setMessage(IslandMessage(id: UUID(), tone: danger ? .danger : (state == "status" ? .success : .neutral),
                                              text: text, isProgress: state == "dictation", onCancel: nil,
                                              detail: state == "long-message" ? "The text is on the clipboard instead" : nil))
            }
            panel.setOpen(open, animated: false)
            return panel
        }, prepare: { window in
            guard let panel = window as? IslandPanel else { return }
            panel.setOpen(open, animated: false)
            if state == "opening-mid" { panel.presentOpening(progress: 0.5, height: NotchcastTheme.Launcher.size.height) }
        })
    }

    /// The end of the opening: the palette in the frame the island grew into. Beside a camera the black stays
    /// behind it as the camera band and the frame; on a monitor the black has faded out under the glass.
    private static func launcherEnd(_ core: AppCore, display: CGRect, notch: CGRect?, suffix: String) -> GalleryPage {
        GalleryPage(name: "launcher-opening-end-\(suffix)", types: ["RootPaletteView", "LauncherList"], makeWindow: {
            let panel = IslandPanel(screenFrame: display, hardwareNotch: notch)
            panel.setLauncher(height: NotchcastTheme.Launcher.size.height, animated: false)
            let canvas = panel.frame
            let shape = panel.outline.path
            let launcher = panel.launcherFrame ?? .zero
            let local = CGRect(x: launcher.minX - canvas.minX, y: canvas.maxY - launcher.maxY,
                               width: launcher.width, height: launcher.height)
            NotchcastPreferences.shared.set(.smallCommands, false)
            NotchcastPreferences.shared.set(.launcherNumberKeys, false)
            core.appIndex.refreshNotchcastCommands()
            core.appIndex.setCustomCommands([])
            core.palette.prepare(mode: .launcher)
            core.palette.noteCommandHeld(false)
            core.palette.query = ""
            let flip = CGAffineTransform(translationX: 0, y: canvas.height).scaledBy(x: 1, y: -1)
            let view = ZStack(alignment: .topLeading) {
                Color.clear
                if notch != nil { Path(shape).transform(flip).fill(NotchcastTheme.Colors.surface) }
                RootPaletteView().paletteEnvironment(core)
                    .frame(width: local.width, height: local.height)
                    .offset(x: local.minX, y: local.minY)
            }
            return window(view, size: canvas.size, dark: true)
        }, settle: .milliseconds(500))
    }

    /// Both candidate levels side by side, moving, as the debug command shows them.
    private static func visualizers() -> GalleryPage {
        GalleryPage(name: "island-visualizers", types: ["IslandVisualizerComparisonView", "IslandSpectrumBars",
                                                          "IslandLevelBars"], makeWindow: {
            let view = IslandVisualizerComparisonView(isPlaying: true, visibleOverride: true)
            let hosting = NSHostingView(rootView: view)
            return window(view, size: hosting.fittingSize, dark: true)
        }, settle: .milliseconds(700))
    }
}
#endif
