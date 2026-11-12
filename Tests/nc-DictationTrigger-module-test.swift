// notchcast-sources: Tinycast/Features/DictationTrigger/DictationTriggerModule*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Dictation/DictationFamily.swift Tests/dictation-family-stubs.swift
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift

import Observation

@MainActor enum NotchcastCore { static let eventTapHub = 0 }
@MainActor @Observable final class HotKeys {
    var recordingAction: String?
    var globeReserved = false
}
@MainActor final class AppCore {
    let dictationCoordinator = DictationCoordinator()
    let hotKeys = HotKeys()
}
enum NotchcastFeature { case dictationEnglish }
@MainActor final class DictationTriggerManager {
    enum Action { case start, finish, cancel }
    static var latest: DictationTriggerManager?
    let action: (Action) -> Void
    var configurations: [(Bool, Bool)] = []
    var stops = 0
    init(hub: Int, isRecording: @escaping () -> Bool, action: @escaping (Action) -> Void) {
        self.action = action
        Self.latest = self
    }
    func setEnabled(_ enabled: Bool, isPaused: Bool) { configurations.append((enabled, isPaused)) }
    func stop() { stops += 1 }
}

@main struct TriggerModuleTest {
    @MainActor static func main() async {
        let core = AppCore()
        let module = NotchcastCore.makeDictationTrigger(core)
        let manager = DictationTriggerManager.latest!
        precondition(manager.configurations.isEmpty)
        module.start()
        module.start()
        precondition(manager.configurations.count == 1 && core.hotKeys.globeReserved)
        manager.action(.start)
        manager.action(.finish)
        manager.action(.cancel)
        precondition(core.dictationCoordinator.starts == 1)
        precondition(core.dictationCoordinator.finishes == 1)
        precondition(core.dictationCoordinator.cancels == 1)
        core.hotKeys.recordingAction = "test"
        for _ in 0..<100 { await Task.yield() }
        precondition(manager.configurations.last?.1 == true)
        core.dictationCoordinator.isEnabled = false
        for _ in 0..<100 { await Task.yield() }
        precondition(!core.hotKeys.globeReserved && manager.configurations.last?.0 == false)
        module.stop()
        module.stop()
        precondition(manager.stops == 1 && !core.hotKeys.globeReserved)
        print("PASS trigger module lifecycle, observation and action routing")
    }
}
