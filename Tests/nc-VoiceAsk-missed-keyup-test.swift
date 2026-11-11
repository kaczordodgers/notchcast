// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskInput.swift
// notchcast-kit: input
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit

@MainActor final class VoiceAskModule {
    var keyCode: Int64 = 105
    var onStart: (@MainActor () -> Void)?
    var onStop: (@MainActor () -> Void)?
    var presses: [Bool] = []
    func start() { onStart?() }
    func stop() { onStop?() }
    func press(alone: Bool) { presses.append(alone) }
    func release() {}
    func chord() {}
}

@main @MainActor
struct VoiceAskMissedKeyUpTests {
    static func main() {
        let hub = EventTapHub()
        let module = VoiceAskModule()
        let input = VoiceAskInput(hub: hub, module: module)
        module.start()
        // Key A goes down while observed; its key-up is hidden by Secure Input and never arrives.
        hub.send(.init(type: .keyDown, flags: [], keyCode: 0))
        // Minutes later, the user taps the ask key alone, twice.
        for _ in 0..<2 {
            hub.send(.init(type: .keyDown, flags: [], keyCode: 105))
            hub.send(.init(type: .keyUp, flags: [], keyCode: 105))
        }
        withExtendedLifetime(input) {}
        guard module.presses == [true, true] else {
            print("FAIL ask key alone after a missed key-up pressed as chord: presses=\(module.presses)")
            exit(1)
        }
        print("PASS VoiceAsk recovers from a missed key-up")
    }
}
