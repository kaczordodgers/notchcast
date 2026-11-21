import Foundation
import Observation

/// Shows a dictation session on the island in place of stock's capsule, and lends it the keyboard.
@MainActor
final class DictationIslandCoordinator {
    private var session = DictationIslandSession()
    private weak var controller: DictationPanelController?
    private var presenter: (any IslandPresenting)?
    private var covered: @MainActor () -> Bool = { false }
    private var copies: @MainActor () -> Bool = { false }
    private var captureDisplay: @MainActor () -> Void = {}
    private var typingDisplay: @MainActor () -> UInt32? = { nil }
    private var showMissingCleanupModelHUD: @MainActor () -> Void = {}
    private let now: @MainActor () -> TimeInterval
    private let sleep: @MainActor (Duration) async throws -> Void
    private var ticker: Task<Void, Never>?
    private var keysFocused = false
    private var shown: IslandNotice?

    init(now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.now = now
        self.sleep = sleep
    }

    isolated deinit { ticker?.cancel() }

    func start(core: AppCore, captureDisplay: @escaping @MainActor () -> Void,
               typingDisplay: @escaping @MainActor () -> UInt32?) {
        let dictation = core.dictationCoordinator
        attach(
            presenter: core.islandPresenter,
            covered: { [weak core] in core.map { $0.palette.isVisible || $0.isShowingDialog } ?? false },
            copies: { [weak core, weak dictation] in
                dictation?.field == nil && core?.settings.dictationDestination.pastes == false
            },
            captureDisplay: captureDisplay, typingDisplay: typingDisplay)
        let stock = dictation.showMessage
        showMissingCleanupModelHUD = { stock(DictationIslandSession.missingCleanupModel, .danger) }
        dictation.showMessage = { [weak self] text, tone in
            if self?.message(text) != true { stock(text, tone) }
        }
        dictation.didReset = { [weak self] in self?.reset(completed: $0) }
        let extras = core.dictationExtras
        extras.cleaningUp = { [weak self] in self?.cleaningUp() }
        extras.cleanupFailed = { [weak self] in self?.cleanupFailed() ?? false }
        extras.delivered = { [weak self] in self?.delivered(empty: $0) }
    }

    /// The seam a Debug scene drives too, with its own presenter and no microphone.
    func attach(presenter: any IslandPresenting, covered: @escaping @MainActor () -> Bool,
                copies: @escaping @MainActor () -> Bool, captureDisplay: @escaping @MainActor () -> Void = {},
                typingDisplay: @escaping @MainActor () -> UInt32? = { nil }) {
        self.presenter = presenter
        self.covered = covered
        self.copies = copies
        self.captureDisplay = captureDisplay
        self.typingDisplay = typingDisplay
        DictationPanelController.stand = { [weak self] in self?.stand(in: $0) }
    }

    /// `show()` returns before stock resets the capsule's state, so the stand-in resets it.
    private func stand(in controller: DictationPanelController) {
        self.controller = controller
        controller.state.phase = .listening
        controller.state.levels = Array(repeating: 0, count: controller.state.levels.count)
        clear()
        session.begin(copies: copies(), at: now())
        captureDisplay()
        place()
        let generation = session.generation
        keysFocused = false
        presenter?.holdKeys(for: IslandNotice.dictationID, onFocus: { [weak self] focused in
            guard let self, session.generation == generation, session.holdsKeys else { return }
            keysFocused = focused
            post()
        }, onKey: { [weak self, weak controller] key in
            guard let self, session.generation == generation, session.holdsKeys else { return }
            switch key {
            case .accept: controller?.onAccept?()
            case .cancel: controller?.onCancel?()
            }
        })
        post()
        watch(generation: generation)
        startTicker(generation: generation)
    }

    private func startTicker(generation: Int) {
        ticker?.cancel()
        ticker = Task { [weak self, sleep] in
            while !Task.isCancelled {
                do { try await sleep(.seconds(1)) } catch { return }
                guard !Task.isCancelled, self?.tick(generation: generation, places: true) == true else { return }
            }
        }
    }

    private func place() {
        let display = typingDisplay()
        if session.place(on: display) { presenter?.place(notice: IslandNotice.dictationID, on: display) }
    }

    private func tick(generation: Int, places: Bool = false) -> Bool {
        guard let state = controller?.state, state.phase == .listening,
              session.generation == generation, session.phase == .recording else { return false }
        if places { place() }
        if session.hear(levels: state.levels, at: now()) { post() }
        return true
    }

    /// Re-arms after every change while its session lives; levels arrive about 20 times a second.
    private func watch(generation: Int) {
        guard let state = controller?.state, session.generation == generation,
            session.phase == .recording || session.phase == .transcribing
        else { return }
        withObservationTracking {
            _ = state.phase
            _ = state.levels
        } onChange: { [weak self] in
            Task { @MainActor in self?.changed(generation: generation) }
        }
    }

    private func changed(generation: Int) {
        guard let state = controller?.state, session.generation == generation else { return }
        if state.phase == .transcribing {
            ticker?.cancel()
            ticker = nil
            if session.transcribe() {
                place()
                post()
            }
        } else {
            _ = tick(generation: generation)
        }
        watch(generation: generation)
    }

    func cleaningUp() {
        if session.cleanUp() { post() }
    }

    /// True when the island reports the raw paste; false leaves the sentence to the caller.
    func cleanupFailed() -> Bool { session.cleanupFailed(covered: covered()) }

    func delivered(empty: Bool) {
        session.delivered(empty: empty)
        presenter?.releaseKeys()
    }

    /// True when the island takes stock's report in place of its sentence under the island.
    func message(_ text: String) -> Bool { session.message(text, covered: covered()) }

    func reset(completed: Bool) {
        guard session.isLive else { return }
        ticker?.cancel()
        ticker = nil
        let settles = session.end(completed: completed)
        presenter?.releaseKeys()
        guard completed else { return clear() }
        guard settles else { return }
        let generation = session.generation
        // One hop later, so stock's report raised right after `reset` in the same turn is counted.
        Task { @MainActor [weak self] in self?.settle(generation: generation) }
    }

    private func settle(generation: Int) {
        let isCovered = covered()
        if let outcome = session.settle(generation: generation, covered: isCovered) {
            if isCovered {
                clear()
                showMissingCleanupModelHUD()
                return
            }
            let notice = IslandNotice(dictation: outcome)
            shown = notice
            presenter?.post(notice, onTap: nil)
        } else if !session.isLive {
            clear()
        }
    }

    private func clear() {
        guard shown != nil else { return }
        shown = nil
        presenter?.end(notice: IslandNotice.dictationID)
    }

    private func post() {
        guard let notice = IslandNotice(dictation: session, keysFocused: keysFocused), notice != shown else { return }
        shown = notice
        presenter?.post(notice, onTap: nil)
    }

    #if DEBUG
    var phase: DictationIslandSession.Phase { session.phase }
    var holdsKeys: Bool { session.holdsKeys && keysFocused }
    #endif
}
