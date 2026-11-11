// notchcast-sources: Tinycast/Features/PasteTools/Model/*.swift
// notchcast-sources: Tinycast/Features/PasteTools/Service/PasteImageModule.swift
// notchcast-kit: platform input
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit
import Carbon.HIToolbox

@MainActor protocol NotchcastModule { func start(); func stop() }
@MainActor extension Paster {
    static func postCommandV() { preconditionFailure("The harness never pastes") }
}
enum FinderImageService { static func save(_ png: Data) -> Bool { false } }

@main @MainActor
struct PasteImageModuleTests {
    static func main() async {
        let board = NSPasteboard(name: .init("nc-paste-image-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setData(Data([0x89]), forType: .png)
        let hub = EventTapHub()
        let module = PasteImageModule(hub: hub, pasteboard: board.name, finderIsFrontmost: { true })
        func send(_ down: Bool = true, flags: CGEventFlags = .maskCommand, repeatKey: Bool = false,
                  synthetic: Bool = false) -> EventTapHub.Verdict {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)!
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            if synthetic { event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag) }
            return hub.handler!(down ? .keyDown : .keyUp, event)
        }
        module.start()
        module.start()
        precondition(hub.consumerCount == 1, "Start twice registers once")
        precondition(send(synthetic: true) == .pass, "Its own replayed Command-V passes")
        precondition(send() == .swallow, "Command-V over an image in Finder is taken")
        precondition(send(flags: [], repeatKey: true) == .swallow, "Its repeats stay taken")
        precondition(send(false, flags: []) == .swallow, "Its release stays taken")
        precondition(send(false) == .pass, "A second release passes")
        board.clearContents()
        board.setString("text", forType: .string)
        module.clipboardTick()
        precondition(send() == .pass, "Command-V over text in Finder passes through untouched")
        precondition(send(repeatKey: true) == .pass, "Its repeats pass")
        precondition(send(false) == .pass, "Its release passes")
        board.clearContents()
        board.setData(Data([0x89]), forType: .png)
        precondition(send() == .pass, "The tap never reads the pasteboard: an image the main actor has not seen passes")
        precondition(send(false) == .pass, "Its release passes")
        try? await Task.sleep(for: .seconds(1))
        precondition(send() == .swallow, "The module's own half-second tick takes the image")
        precondition(send(false) == .swallow, "Its release stays taken")
        precondition(send(flags: [.maskCommand, .maskShift]) == .pass, "Other chords pass")
        module.stop()
        module.stop()
        precondition(hub.consumerCount == 0 && hub.handler == nil)
        print("✓ PasteImage module: start once, take, repeat, release, text and chord pass-through checks passed")
    }
}
