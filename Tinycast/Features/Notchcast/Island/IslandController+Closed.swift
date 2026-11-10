import AppKit

extension IslandController {
    /// A message first, then live activities by rank (a meeting about to start as a card), then the song. The first
    /// is the main item; the second goes in the bubble or the row below the camera.
    static func closedState(message: IslandMessage?, activities: [IslandActivity], track: IslandTrack?)
        -> IslandClosedState
    {
        let items = [message.map(IslandClosedItem.message)] + activities.map { Optional(item($0)) }
            + [track.map(IslandClosedItem.music)]
        let shown = items.compactMap { $0 }
        return IslandClosedState(main: shown.first, second: shown.dropFirst().first)
    }

    static func track(_ playing: NowPlaying?) -> IslandTrack? {
        guard let playing else { return nil }
        return IslandTrack(title: playing.title, artist: playing.artist,
                           artwork: playing.artwork.flatMap(NSImage.init(data:)), isPlaying: playing.isPlaying)
    }

    private static func item(_ activity: IslandActivity) -> IslandClosedItem {
        guard let meeting = activity.meeting else { return .activity(activity) }
        let color = meeting.tint.flatMap {
            $0.count == 3 ? MeetingEvent.CalendarColor(red: $0[0], green: $0[1], blue: $0[2]) : nil
        }
        let link = meeting.link.flatMap { MeetingLink.detect(in: $0.absoluteString) }
        return .card(IslandCard(
            kind: .meeting(start: meeting.start, color: color), title: activity.title,
            action: link.map { link in { Task { _ = await MeetingLauncher.join(link, browserBundleID: nil) } } }))
    }

    func watchLauncher() {
        let center = NotificationCenter.default
        launcherObservations = [
            NotificationToken(center.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let palette = NSApp.keyWindow as? PalettePanel else { return }
                    self?.launcherDidShow(palette)
                }
            }, center: center),
            NotificationToken(center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.restoreAfterLauncher() }
            }, center: center),
        ]
    }

    /// Hover and click must not open an island under the launcher.
    var launcherIsUp: Bool { NSApp.windows.contains { $0 is PalettePanel && $0.isVisible } }

    func restoreAfterLauncher() {
        guard !launcherIsUp else { return }
        panels.forEach { $0.launcherDidClose() }
    }

    /// The launcher replaces an open island it hangs from or would sit under, pinned or not.
    private func launcherDidShow(_ palette: NSWindow) {
        // The compact bar's window carries a glass outset around the visible capsule.
        let frame = palette.frame
        let launcher = frame.height < NotchcastTheme.Launcher.size.height
            ? frame.insetBy(dx: Theme.Size.paletteGlassOutset, dy: Theme.Size.paletteGlassOutset) : frame
        let host = NotchcastLauncherPlacement.island(hosting: launcher, among: panels)
        if isOpen, let openPanel, NotchcastLauncherPlacement.displaces(openPanel, launcher: launcher, host: host) {
            close()
        }
    }
}
