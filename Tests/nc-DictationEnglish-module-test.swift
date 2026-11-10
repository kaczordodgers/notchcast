// notchcast-sources: Tinycast/Features/DictationEnglish/Service/DictationEnglishModule*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Dictation/DictationFamily.swift Tests/dictation-family-stubs.swift
// notchcast-kit: input
import AppKit
import Carbon.HIToolbox

@MainActor protocol NotchcastModule { func start(); func stop() }

@MainActor final class EventTapHub {
    struct Event {
        let keyCode: Int64
        let flags: CGEventFlags
        var isSynthetic = false
        var isRepeat = false
    }
    enum Verdict: Sendable { case pass, swallow }
    var handlers: [UUID: @MainActor @Sendable (Event) -> Void] = [:]
    var synchronous: [UUID: @Sendable (CGEventType, CGEvent) -> Verdict] = [:]
    func register(mask: CGEventMask, handler: @escaping @MainActor @Sendable (Event) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }
    func registerSynchronous(
        mask: CGEventMask, handler: @escaping @Sendable (CGEventType, CGEvent) -> Verdict
    ) -> UUID {
        let id = UUID()
        synchronous[id] = handler
        return id
    }
    func remove(_ id: UUID) { handlers[id] = nil; synchronous[id] = nil }
    func send() {
        for handler in handlers.values {
            handler(Event(keyCode: Int64(kVK_ANSI_Grave), flags: .maskSecondaryFn))
        }
    }
}

enum Paster { static let tinycastEventTag: Int64 = 1 }
enum DialogTone { case danger }
@MainActor final class AppCore {
    static let shared = AppCore()
    var messages: [String] = []
    func showMessage(_ message: String, tone: DialogTone) { messages.append(message) }
}
@main struct EnglishModuleTest {
    @MainActor static func main() async {
        let hub = EventTapHub()
        let coordinator = DictationCoordinator()
        let module = DictationEnglishModule(hub: hub, coordinator: coordinator)
        module.start()
        module.start()
        precondition(hub.handlers.count == 1 && hub.synchronous.count == 1)
        hub.send()
        precondition(coordinator.starts == 1 && coordinator.triggerIsRecording)
        hub.send()
        precondition(coordinator.finishes == 1 && !coordinator.triggerIsRecording)
        hub.send()
        module.stop()
        module.stop()
        precondition(coordinator.englishCancels == 1 && !coordinator.triggerIsRecording)
        precondition(hub.handlers.isEmpty && hub.synchronous.isEmpty)
        hub.send()
        precondition(coordinator.starts == 2)
        let result = await DictationCoordinator.englishTranscriptStage!("fixture", "Polish")
        precondition(result == "fixture")
        precondition(AppCore.shared.messages == [
            String(localized: "English translation failed; using the original transcript")
        ])
        DictationCoordinator.englishTranscriptStage = nil
        print("PASS English module registration, command, stop and failure message")
    }
}
