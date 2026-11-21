// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/DictationIslandCoordinator.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/DictationIslandNotice.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/DictationIslandSession.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandKeyHold.swift Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Features/Dictation/UI/DictationPanel.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationSpectrum.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/Interaction/AnimatedPanel.swift Tinycast/DesignSystem/Interaction/Motion.swift
// notchcast-sources: Tinycast/Platform/Appearance.swift
// notchcast-sources: notchcast/vendor/Obsidian/ObsidianTokens.swift

import AppKit

@MainActor
@main
enum DictationIslandFocusTest {
    static func main() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate()
        let presenter = KeyPresenter()
        let clock = ManualClock()
        let island = DictationIslandCoordinator(now: { clock.now }, sleep: { await clock.sleep($0) })
        island.attach(presenter: presenter, covered: { false }, copies: { false })
        let capsule = DictationPanelController()
        var accepted = 0
        var cancelled = 0
        capsule.onAccept = { accepted += 1 }
        capsule.onCancel = { cancelled += 1; island.reset(completed: false) }

        let document = NSPanel(
            contentRect: CGRect(x: 50, y: 50, width: 100, height: 100), styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered, defer: false)
        defer { document.orderOut(nil) }

        capsule.show()
        await eventually("the first attempt settles") { presenter.focus.last == true }
        precondition(presenter.notice?.text.contains("Return to Paste") == true)
        await eventually("recording schedules a tick") { clock.pending != nil }
        clock.advance()
        await eventually("silence advances the readout") { presenter.notice?.progress?.readout == "0:01" }
        precondition(presenter.notice?.meter == [0, 0, 0, 0])

        let first = presenter.focus.count
        document.makeKeyAndOrderFront(nil)
        precondition(NSApp.keyWindow === document, "the document took key focus during recording")
        precondition(presenter.focus.count == first, "recovery waits until after resignKey returns")
        await eventually("a resigned panel tries again") { presenter.focus.count > first }
        deliver(36, "\r")
        if presenter.focus.last == true {
            precondition(accepted == 1, "Return goes to dictation after it reclaims focus")
        } else {
            precondition(accepted == 0 && presenter.notice?.text == "Recording dictation", "the key hint is gone")
            precondition(presenter.notice?.spoken == "Recording dictation")
        }

        let second = presenter.focus.count
        island.reset(completed: false)
        if clock.pending != nil { clock.advance() }
        await eventually("the cancelled tick exits") { clock.sleeps == clock.wakes }
        capsule.show()
        await eventually("the next session starts with keys") {
            presenter.focus.count > second && presenter.focus.last == true
        }
        precondition(presenter.notice?.progress?.readout == "0:00", "the next session has its own clock")
        await eventually("the next session schedules its own tick") { clock.pending != nil }
        deliver(53, "\u{1b}")
        precondition(cancelled == 1 && presenter.notice == nil, "Escape cancels the next session")
        clock.advance()
        await eventually("Escape cancels its tick") { clock.sleeps == clock.wakes }
        precondition(presenter.notice == nil && clock.pending == nil, "a cancelled tick cannot repost or start another")
        print("PASS dictation key recovery, restart and silent clock")
    }

    private static func eventually(_ message: String, _ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        precondition(condition(), message)
    }

    private static func deliver(_ code: UInt16, _ character: String) {
        guard let window = NSApp.keyWindow, let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)
        else { preconditionFailure("the key window must receive the event") }
        window.sendEvent(event)
    }

    @MainActor
    private final class ManualClock {
        var now: TimeInterval = 0
        var pending: CheckedContinuation<Void, Never>?
        var sleeps = 0
        var wakes = 0

        func sleep(_ duration: Duration) async {
            precondition(duration == .seconds(1) && pending == nil)
            sleeps += 1
            await withCheckedContinuation { pending = $0 }
            wakes += 1
        }

        func advance() {
            now += 1
            guard let pending else { preconditionFailure("recording must have scheduled a tick") }
            self.pending = nil
            pending.resume()
        }
    }

    private final class KeyPresenter: IslandPresenting {
        let keyHold = IslandKeyHold()
        var notice: IslandNotice?
        var focus: [Bool] = []

        func holdKeys(for notice: String, onFocus: @escaping @MainActor (Bool) -> Void,
                      onKey: @escaping @MainActor (IslandHeldKey) -> Void) {
            keyHold.hold(near: nil, during: notice, onFocus: { [weak self] focused in
                self?.focus.append(focused)
                onFocus(focused)
            }, onKey: onKey)
        }

        func releaseKeys() { keyHold.release() }
        func showLevel(_ level: IslandLevel) {}
        func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { self.notice = notice }
        func end(notice id: String) { notice = nil }
        func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
        func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
    }
}

@MainActor
final class AppCore {
    final class Dictation {
        enum Tone { case danger }
        var field: Int?
        var showMessage: (String, Tone) -> Void = { _, _ in }
        var didReset: (Bool) -> Void = { _ in }
    }

    final class Extras {
        var cleaningUp: () -> Void = {}
        var cleanupFailed: () -> Bool = { false }
        var delivered: (Bool) -> Void = { _ in }
    }

    let dictationCoordinator = Dictation()
    let dictationExtras = Extras()
    var islandPresenter: any IslandPresenting { fatalError("the harness attaches its own presenter") }
    struct Palette { let isVisible = false }
    struct Settings { let dictationDestination = Destination() }
    struct Destination { let pastes = true }

    let palette = Palette()
    let settings = Settings()
    let isShowingDialog = false
}
