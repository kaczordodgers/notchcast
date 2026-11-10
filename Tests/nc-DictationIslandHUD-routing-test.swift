// notchcast-sources: Tinycast/Features/DictationIslandHUD/Model/*.swift
// notchcast-sources: Tinycast/Features/DictationIslandHUD/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastCore+RemoteResult.swift
// notchcast-kit: core host
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

@main @MainActor
struct DictationIslandHUDTest {
    static func settle() async { for _ in 0..<50 { await Task.yield() } }
    // Upstream's hideProgress reaches the island through MessageHUDController.dismiss, i.e. this call.
    static func hideProgress() { IslandHUDRouter.dismiss() }

    static func main() async {
        typealias Policy = DictationIslandHUDPolicy
        let table: [(Policy.Phase, Bool, Bool, Policy.Presentation)] = [
            (.listening, true, true, .listening), (.listening, true, false, .capsule),
            (.listening, false, true, .capsule), (.listening, false, false, .capsule),
            (.transcribing, true, true, .transcribing), (.transcribing, true, false, .capsule),
            (.transcribing, false, true, .capsule), (.transcribing, false, false, .capsule)
        ]
        for (phase, enabled, available, expected) in table {
            precondition(Policy.presentation(phase: phase, enabled: enabled, islandAvailable: available) == expected)
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
        hideProgress()
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

        var huds: [String] = []
        NotchcastHost.current.showMessage = { text, _ in huds.append(text) }
        NotchcastCore.remoteResult("Backup done")
        precondition(center.message?.text == "Backup done" && huds.isEmpty)
        hideProgress()
        precondition(center.message?.text == "Backup done", "upstream hideProgress leaves a remote result")
        center.hasPresenter = false
        NotchcastCore.remoteResult("No presenter")
        precondition(huds == ["No presenter"], "with no presenter the result reaches the HUD")
        print("Remote result: island when presented, HUD otherwise, untouched by hideProgress passed")
    }
}
