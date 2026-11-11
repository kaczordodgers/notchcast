// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskInput.swift
// notchcast-kit: input
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit

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
