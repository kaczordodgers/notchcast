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
        var frontmost = true
        var frontmostChecks = 0
        let finderIsFrontmost: @MainActor () -> Bool = { frontmostChecks += 1; return frontmost }
        let module = PasteImageModule(hub: hub, pasteboard: board.name, finderIsFrontmost: finderIsFrontmost)
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
        module.refresh()
        precondition(send() == .pass, "Command-V over text in Finder passes through untouched")
        precondition(send(repeatKey: true) == .pass, "Its repeats pass")
        precondition(send(false) == .pass, "Its release passes")
        board.clearContents()
        board.setData(Data([0x89]), forType: .png)
        precondition(send() == .pass, "The tap never reads the pasteboard: an image the hook has not reported passes")
        precondition(send(false) == .pass, "Its release passes")
        module.refresh()
        precondition(send() == .swallow, "The clipboard hook takes the image")
        precondition(send(false) == .swallow, "Its release stays taken")
        precondition(send(flags: [.maskCommand, .maskShift]) == .pass, "Other chords pass")
        frontmost = false
        module.refresh()
        precondition(send() == .pass, "The hook takes nothing while Finder is behind")
        precondition(send(false) == .pass, "Its release passes")
        module.stop()
        module.stop()
        precondition(hub.consumerCount == 0 && hub.handler == nil)
        // The stopped module ignores its queued pastes, so only now may the harness suspend.
        board.clearContents()
        let second = PasteImageModule(hub: hub, pasteboard: board.name, finderIsFrontmost: finderIsFrontmost)
        second.start()
        board.setData(Data([0x89]), forType: .png)
        frontmost = true
        precondition(send() == .pass, "An image copied behind Finder passes until Finder comes to the front")
        precondition(send(false) == .pass, "Its release passes")
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(200))
        precondition(send() == .swallow, "Finder coming to the front reads the pasteboard once")
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        second.stop()
        let checksAtStop = frontmostChecks
        try? await Task.sleep(for: .milliseconds(200))
        precondition(frontmostChecks == checksAtStop, "An activation queued before stop reads nothing after it")
        print("✓ PasteImage module: start once, hook, activation, repeat, release, text and chord pass-through checks passed")
    }
}
