// notchcast-sources: Tinycast/Features/DictationEnglish/Service/DictationEnglishModule*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Dictation/DictationFamily.swift Tests/dictation-family-stubs.swift
// notchcast-kit: input host
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit
import Carbon.HIToolbox

@MainActor protocol NotchcastModule { func start(); func stop() }
extension EventTapHub {
    func send() { send(Event(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_Grave))) }
}
enum DialogTone { case danger }
@main struct EnglishModuleTest {
    @MainActor static func main() async {
        var messages: [String] = []
        NotchcastHost.current.showMessage = { text, _ in messages.append(text) }
        let hub = EventTapHub()
        let coordinator = DictationCoordinator()
        let module = DictationEnglishModule(hub: hub, coordinator: coordinator)
        module.start()
        module.start()
        precondition(hub.handlers.count == 1 && hub.synchronousHandlers.count == 1)
        hub.send(EventTapHub.Event(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_Grave), isSynthetic: true))
        hub.send(EventTapHub.Event(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_Grave), isRepeat: true))
        precondition(coordinator.starts == 0 && !coordinator.triggerIsRecording)
        hub.send()
        precondition(coordinator.starts == 1 && coordinator.triggerIsRecording)
        hub.send(EventTapHub.Event(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_Grave), isSynthetic: true))
        hub.send(EventTapHub.Event(flags: .maskSecondaryFn, keyCode: Int64(kVK_ANSI_Grave), isRepeat: true))
        precondition(coordinator.finishes == 0 && coordinator.triggerIsRecording)
        hub.send()
        precondition(coordinator.finishes == 1 && !coordinator.triggerIsRecording)
        hub.send()
        module.stop()
        module.stop()
        precondition(coordinator.englishCancels == 1 && !coordinator.triggerIsRecording)
        precondition(hub.handlers.isEmpty && hub.synchronousHandlers.isEmpty)
        hub.send()
        precondition(coordinator.starts == 2)
        let result = await DictationCoordinator.englishTranscriptStage!("fixture", "Polish")
        precondition(result == "fixture")
        precondition(messages == [
            String(localized: "English translation failed; using the original transcript")
        ])
        DictationCoordinator.englishTranscriptStage = nil
        print("PASS English module registration, command, stop and failure message")
    }
}
