// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskInput.swift
// notchcast-kit: input
import AppKit

enum Paster { static let tinycastEventTag: Int64 = 12345 }

@MainActor final class EventTapHub {
    struct Event {
        let type: CGEventType
        let flags: CGEventFlags
        let keyCode: Int64
        var isRepeat = false
        var isSynthetic = false
    }
    enum Verdict { case pass, swallow }
    var handlers: [UUID: @MainActor @Sendable (Event) -> Void] = [:]
    func register(mask: CGEventMask, handler: @escaping @MainActor @Sendable (Event) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }
    func registerSynchronous(mask: CGEventMask,
                             handler: @escaping @Sendable (CGEventType, CGEvent) -> Verdict) -> UUID { UUID() }
    func remove(_ id: UUID) { handlers[id] = nil }
    func send(_ event: Event) { handlers.values.forEach { $0(event) } }
}

@MainActor final class VoiceAskModule {
    var keyCode: Int64 = 105
    var onStart: (@MainActor () -> Void)?
    var onStop: (@MainActor () -> Void)?
    var presses: [Bool] = []
    var releases = 0
    func start() { onStart?() }
    func stop() { onStop?() }
    func press(alone: Bool) { presses.append(alone) }
    func release() { releases += 1 }
    func chord() {}
}

@main @MainActor
struct VoiceAskInputTests {
    static func main() {
        let hub = EventTapHub()
        let module = VoiceAskModule()
        let input = VoiceAskInput(hub: hub, module: module)
        module.start()
        module.start()
        precondition(hub.handlers.count == 1, "Start twice observes once")
        hub.send(.init(type: .keyDown, flags: [], keyCode: 105))
        precondition(module.presses == [true], "The ask key alone presses")
        module.stop()
        precondition(hub.handlers.isEmpty, "Stop ends the observation")
        hub.send(.init(type: .keyUp, flags: [], keyCode: 105))
        precondition(module.releases == 0)
        withExtendedLifetime(input) {}
        print("✓ VoiceAsk input: start once, ask key press and stop checks passed")
    }
}
