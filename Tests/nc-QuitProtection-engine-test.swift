import Foundation

@main @MainActor
struct QuitProtectionTests {
    static let target = QuitProtectionEngine.Target(processIdentifier: 42, bundleIdentifier: "test.editor", name: "Editor")
    static let other = QuitProtectionEngine.Target(processIdentifier: 43, bundleIdentifier: "test.editor", name: "Editor")
    static let q = QuitProtectionEngine.Key(code: 12, commandCharacter: "q")
    static let w = QuitProtectionEngine.Key(code: 13, commandCharacter: "w")
    static var checks = 0

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }

    @MainActor static func main() {
        check(QuitProtectionAppName.displayName("My.app.editor.app") == "My.app.editor", "Only trailing suffix removed")
        check(QuitProtectionAppName.displayName("My.app.editor") == "My.app.editor", "Internal suffix preserved")
        check(QuitProtectionAppName.displayName("Editor") == "Editor", "Plain name preserved")
        var engine = QuitProtectionEngine(configuration: .init(mode: .doublePress))
        let first = engine.consume(.keyDown(q, .command, isRepeat: false), at: 10, target: target)
        guard case .swallow(let notice) = first else { fatalError("First quit must be swallowed") }
        check(notice?.text == "Press ⌘Q again to quit Editor", "Notice names the target")
        check(engine.consume(.keyDown(q, .command, isRepeat: true), at: 10.1, target: target) == .swallow(nil),
              "Repeat cannot confirm")
        check(engine.consume(.keyDown(q, .command, isRepeat: false), at: 10.2, target: target) == .swallow(nil),
              "A release is required between presses")
        check(engine.consume(.keyUp(q), at: 10.3, target: target) == .swallow(nil), "First release swallowed")
        check(engine.consume(.keyDown(q, .command, isRepeat: false), at: 10.6, target: target) == .quit(target),
              "600 ms boundary confirms")
        check(engine.consume(.keyUp(q), at: 10.7, target: target) == .swallow(nil), "Confirmed release swallowed")
        check(engine.consume(.tick, at: 11, target: target) == .pass, "Confirmation runs only once")

        engine.reset()
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 20, target: target)
        _ = engine.consume(.keyUp(q), at: 20.1, target: target)
        check(isNotice(engine.consume(.keyDown(q, .command, isRepeat: false), at: 20.601, target: target)),
              "Expired press starts a new window")
        _ = engine.consume(.keyUp(q), at: 20.7, target: target)
        check(isNotice(engine.consume(.keyDown(q, .command, isRepeat: false), at: 20.8, target: other)),
              "PID change cannot inherit confirmation")
        _ = engine.consume(.keyUp(q), at: 20.9, target: other)
        _ = engine.consume(.modifiersChanged([]), at: 21, target: other)
        check(isNotice(engine.consume(.keyDown(q, .command, isRepeat: false), at: 21.1, target: other)),
              "Releasing Command cancels confirmation")

        engine.reset()
        check(engine.consume(.keyDown(w, .command, isRepeat: false), at: 30, target: target) == .pass,
              "Close protection is opt-in")
        check(engine.consume(.keyDown(q, [.command, .shift], isRepeat: false), at: 31, target: target) == .pass,
              "Modified shortcuts keep native semantics")
        check(engine.consume(.keyDown(q, [], isRepeat: false), at: 32, target: target) == .pass, "Typing passes")
        check(engine.consume(.keyDown(q, .command, isRepeat: false), at: 33, target: nil) == .pass, "Unknown target passes")
        engine.configuration.exceptions = [target.bundleIdentifier]
        check(engine.consume(.keyDown(q, .command, isRepeat: false), at: 34, target: target) == .pass, "Exception passes")
        engine.configuration = .init(quitEnabled: true, closeEnabled: true, mode: .doublePress)
        check(isNotice(engine.consume(.keyDown(w, .command, isRepeat: false), at: 35, target: target)), "Close starts")
        _ = engine.consume(.keyUp(w), at: 35.1, target: target)
        check(engine.consume(.keyDown(w, .command, isRepeat: false), at: 35.2, target: target) == .close(target),
              "Close returns a close action")
        check(QuitProtectionEngine.Key(code: 12, commandCharacter: "x").shortcut == nil, "Layout wins over keycode")
        check(QuitProtectionEngine.Key(code: 14, commandCharacter: "Q").shortcut == .quit, "Command layout table wins")
        check(QuitProtectionEngine.Key(code: 12, commandCharacter: nil).shortcut == .quit, "No layout uses physical fallback")

        engine.configuration.mode = .hold
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 40, target: target)
        check(engine.consume(.tick, at: 40.799, target: target) == .pass, "Hold before 800 ms waits")
        check(engine.consume(.tick, at: 40.8, target: target) == .quit(target), "800 ms hold confirms")
        check(engine.consume(.tick, at: 40.9, target: target) == .pass, "Hold confirms once")
        _ = engine.consume(.keyUp(q), at: 41, target: target)
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 42, target: target)
        check(engine.consume(.keyUp(q), at: 42.799, target: target) == .swallow(nil), "Early release swallowed")
        check(engine.consume(.tick, at: 43, target: target) == .pass, "Early release cancels hold")
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 44, target: target)
        check(engine.consume(.tick, at: 44.8, target: other) == .pass, "Switching apps cancels hold")
        engine.reset()
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 50, target: target)
        _ = engine.consume(.tick, at: 49, target: target)
        check(engine.consume(.tick, at: 51, target: target) == .pass, "Clock rollback cancels")
        check(engine.consume(.tick, at: .nan, target: target) == .pass, "Invalid clock cancels")
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 60, target: target)
        check(engine.consume(.keyUp(q), at: 60.8, target: target) == .quit(target), "Late key-up confirms a completed hold")
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 61, target: target)
        engine.configuration.quitEnabled = false
        check(engine.consume(.keyUp(q), at: 61.1, target: target) == .swallow(nil), "Config change preserves paired release")
        check(engine.consume(.tick, at: 62, target: target) == .pass, "Config change cancels hold")
        engine.configuration.quitEnabled = true
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 63, target: target)
        let escape = QuitProtectionEngine.Key(code: 53, commandCharacter: nil)
        check(engine.consume(.keyDown(escape, [], isRepeat: false), at: 63.1, target: target) == .swallow(nil),
              "Escape cancels pending confirmation")
        check(engine.consume(.tick, at: 64, target: target) == .pass, "Cancelled hold cannot fire")

        engine.reset()
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 70, target: target)
        _ = engine.consume(.modifiersChanged([]), at: 70.1, target: target)
        check(engine.consume(.keyDown(q, [], isRepeat: false), at: 70.2, target: target) == .pass,
              "Modifier change recovers a lost Q release")
        _ = engine.consume(.keyDown(q, .command, isRepeat: false), at: 71, target: target)
        _ = engine.consume(.keyDown(.init(code: 0, commandCharacter: "a"), [], isRepeat: false), at: 71.1, target: target)
        check(engine.consume(.keyDown(q, [], isRepeat: false), at: 71.2, target: target) == .pass,
              "Another key recovers a lost Q release")
        let suite = "nc.quit.tests.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QuitProtectionStore(defaults: defaults)
        check(store.configuration == .init(), "Stored defaults match engine defaults")
        store.configuration = .init(quitEnabled: false, closeEnabled: true, mode: .hold, exceptions: ["test.app"])
        check(QuitProtectionStore(defaults: defaults).configuration == store.configuration, "Fork-local preferences round trip")
        print("PASS: \(checks) quit-protection checks; no event tap or app termination")
    }

    static func isNotice(_ decision: QuitProtectionEngine.Decision) -> Bool {
        if case .swallow(.some) = decision { return true }
        return false
    }
}
