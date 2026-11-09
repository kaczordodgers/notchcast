// notchcast-sources: Tinycast/Features/Notchcast/Activities/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
import Foundation

enum DialogTone { case neutral, success, danger }
enum Theme {
    enum Duration { static let messageHUD: TimeInterval = 2.4 }
}

/// Dwells end only when the test fires them, so timing never depends on the machine.
@MainActor
final class ManualSleep {
    private(set) var dwells: [TimeInterval] = []
    private var wake: AsyncStream<Void>.Continuation?

    func sleep(_ dwell: TimeInterval) async {
        dwells.append(dwell)
        let stream = AsyncStream<Void> { wake = $0 }
        for await _ in stream { break }
    }

    func fire() async {
        wake?.yield()
        await settle()
    }
}

@MainActor
func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

@main
@MainActor
struct NotchcastActivitiesTests {
    static func main() async {
        for running in [false, true] {
            for enabled in [false, true] {
                for visible in [false, true] {
                    precondition(IslandPresenterPolicy.shouldRegister(
                        running: running, enabled: enabled, visibleOnActiveScreen: visible)
                        == (running && enabled && visible))
                }
            }
        }
        let clock = ManualSleep()
        let center = IslandActivityCenter(sleep: clock.sleep)
        let status = center.begin(IslandActivity(kind: .status, priority: 100, title: "Status"))
        let transfer = center.begin(IslandActivity(kind: .transfer, title: "Transfer"))
        precondition(center.current?.id == transfer)
        let timer = center.begin(IslandActivity(kind: .timer, priority: 1, title: "Timer"))
        precondition(center.current?.id == timer)
        let soon = center.begin(IslandActivity(kind: .timer, priority: 1, title: "Soon",
                                             endDate: Date(timeIntervalSince1970: 1)))
        let equal = center.begin(IslandActivity(kind: .timer, priority: 1, title: "Equal",
                                              endDate: Date(timeIntervalSince1970: 1)))
        precondition(center.current?.id == soon)
        center.finish(soon)
        precondition(center.current?.id == equal)
        center.fail(equal)
        center.fail(timer)
        precondition(center.current?.id == transfer)
        center.update(transfer, title: "Updated", progress: .some(2))
        precondition(center.current?.title == "Updated" && center.current?.progress == 1)
        center.finish(transfer)
        center.finish(status)
        center.update(transfer, title: "Stale")
        precondition(center.current == nil)

        center.showMessage("Old", tone: .success, dwell: 1)
        await settle()
        let shown = center.message?.id
        center.showMessage("New", tone: .danger, dwell: 2)
        await settle()
        precondition(center.message?.id == shown && center.message?.text == "New")
        precondition(clock.dwells == [1, 2])
        await clock.fire()
        precondition(center.message == nil)

        center.showMessage("Replaced", tone: .neutral, dwell: 1)
        await settle()
        let replaced = center.showProgress("Working")
        await clock.fire()
        precondition(center.message?.isProgress == true && center.message?.text == "Working")
        let other = center.showProgress("Other poster")
        center.dismiss(replaced)
        precondition(center.message?.text == "Other poster", "a replaced poster cannot end the notice")
        center.dismiss(other)
        precondition(center.message == nil)

        let shared = IslandActivityCenter.shared
        let preferences = NotchcastPreferences.shared
        let wasOn = preferences.isOn(.islandStatusMessages)
        defer { preferences.set(.islandStatusMessages, wasOn) }
        preferences.set(.islandStatusMessages, true)
        precondition(!IslandHUDRouter.show("Fallback", tone: .success))
        shared.hasPresenter = true
        preferences.set(.islandStatusMessages, false)
        precondition(!IslandHUDRouter.show("Off", tone: .success))
        precondition(!IslandHUDRouter.showProgress("Off", onCancel: nil))
        precondition(shared.message == nil)
        preferences.set(.islandStatusMessages, true)
        precondition(IslandHUDRouter.show("Routed", tone: .danger))
        precondition(shared.message?.text == "Routed")
        var cancelled = false
        precondition(IslandHUDRouter.showProgress("Progress", onCancel: { cancelled = true }))
        shared.message?.onCancel?()
        precondition(cancelled)
        shared.hasPresenter = false
        precondition(!IslandHUDRouter.showProgress("Fallback progress", onCancel: nil))
        precondition(shared.message == nil)
        shared.hasPresenter = true
        precondition(IslandHUDRouter.showProgress("Another progress", onCancel: nil))
        shared.hasPresenter = false
        precondition(!IslandHUDRouter.show("Fallback result", tone: .success))
        precondition(shared.message == nil)
        shared.hasPresenter = true
        precondition(IslandHUDRouter.showProgress("Disabled progress", onCancel: nil))
        preferences.set(.islandStatusMessages, false)
        precondition(!IslandHUDRouter.showProgress("Off", onCancel: nil))
        precondition(shared.message == nil)
        preferences.set(.islandStatusMessages, true)
        precondition(IslandHUDRouter.showProgress("Disabled result", onCancel: nil))
        preferences.set(.islandStatusMessages, false)
        precondition(!IslandHUDRouter.show("Off", tone: .success))
        precondition(shared.message == nil)
        preferences.set(.islandStatusMessages, true)
        precondition(IslandHUDRouter.show("HUD", tone: .success))
        let remote = IslandHUDRouter.post("Remote")
        precondition(remote != nil && shared.message?.text == "Remote")
        IslandHUDRouter.dismiss()
        precondition(shared.message?.text == "Remote", "the HUD cannot end a remote notice")
        shared.dismiss(remote!)
        precondition(shared.message == nil)
        shared.hasPresenter = false
        precondition(IslandHUDRouter.post("No presenter") == nil && shared.message?.text == "No presenter",
                     "a post still enters the center when no presenter shows it")
        let pill = IslandHUDRouter.progress("Pill")
        precondition(pill == nil && shared.message?.text == "No presenter", "a pill needs a presenter")
        preferences.set(.islandStatusMessages, false)
        IslandHUDRouter.dismiss()
        precondition(shared.message?.text == "No presenter", "the HUD cannot end a post")
        print("PASS priority, deadlines, removal, updates, dwell re-arm, replacement, switch, routing and cancellation")
    }
}
