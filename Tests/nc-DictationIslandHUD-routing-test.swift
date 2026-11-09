// notchcast-sources: Tinycast/Features/DictationIslandHUD/Model/*.swift
// notchcast-sources: Tinycast/Features/DictationIslandHUD/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastCore+RemoteResult.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
import AppKit
import Observation

enum DialogTone { case neutral, success, danger }
enum Theme { enum Duration { static let messageHUD: TimeInterval = 2.4 } }
@MainActor enum NotchcastCore {}

@MainActor @Observable final class DictationDisplayState {
    enum Phase { case listening, transcribing }
    var phase: Phase = .listening
}

@MainActor final class AppCore {
    static let shared = AppCore()
    var huds: [String] = []
    func showMessage(_ text: String, tone: DialogTone) { huds.append(text) }
    // Upstream's hideProgress reaches the island through MessageHUDController.dismiss, i.e. this call.
    func hideProgress() { IslandHUDRouter.dismiss() }
}

@main @MainActor
struct DictationIslandHUDTest {
    static func settle() async { for _ in 0..<50 { await Task.yield() } }

    static func main() async {
        for phase in [DictationIslandHUDPolicy.Phase.listening, .transcribing] {
            for enabled in [true, false] {
                for available in [true, false] {
                    let result = DictationIslandHUDPolicy.presentation(
                        phase: phase, enabled: enabled, islandAvailable: available)
                    let expected: DictationIslandHUDPolicy.Presentation = enabled && available
                        ? (phase == .listening ? .listening : .transcribing) : .capsule
                    precondition(result == expected)
                }
            }
        }
        print("Dictation island routing: both phases and capsule fallback passed")

        let preferences = NotchcastPreferences.shared
        let switches: [NotchcastFeature] = [.dictationIslandHUD, .island, .islandStatusMessages]
        let saved = switches.map { preferences.isOn($0) }
        defer { for (feature, on) in zip(switches, saved) { preferences.set(feature, on) } }
        switches.forEach { preferences.set($0, true) }
        let center = IslandActivityCenter.shared
        center.hasPresenter = true
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: NSRect(x: 10, y: 10, width: 100, height: 40), styleMask: [.borderless],
                            backing: .buffered, defer: true)
        let listening = String(localized: "Dictation listening")
        let transcribing = String(localized: "Transcribing dictation")
        let state = DictationDisplayState()
        let pill = DictationIslandHUDService()

        pill.show(panel: panel, state: state)
        precondition(center.message?.text == listening && center.message?.isProgress == true)
        AppCore.shared.hideProgress()
        precondition(center.message?.text == listening, "upstream hideProgress leaves the dictation pill")
        state.phase = .transcribing
        await settle()
        precondition(center.message?.text == transcribing, "the pill follows its phase")
        center.showMessage("Foreign", tone: .neutral, dwell: 5)
        await settle()
        precondition(center.message?.text == transcribing, "a foreign message gives the pill back at once")
        pill.close()
        precondition(center.message == nil, "closing ends the pill's own notice")
        print("Dictation island pill: own handle, survives hideProgress, follows phase passed")

        NotchcastCore.remoteResult("Backup done")
        precondition(center.message?.text == "Backup done" && AppCore.shared.huds.isEmpty)
        AppCore.shared.hideProgress()
        precondition(center.message?.text == "Backup done", "upstream hideProgress leaves a remote result")
        center.hasPresenter = false
        NotchcastCore.remoteResult("No presenter")
        precondition(AppCore.shared.huds == ["No presenter"], "with no presenter the result reaches the HUD")
        print("Remote result: island when presented, HUD otherwise, untouched by hideProgress passed")
    }
}
