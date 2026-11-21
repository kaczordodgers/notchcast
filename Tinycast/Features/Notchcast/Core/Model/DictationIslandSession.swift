import Foundation

/// One dictation session as the island shows it, from the first sound to the result it reports.
struct DictationIslandSession: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle, recording, transcribing, cleaningUp
        /// Reset, waiting one main-actor hop for the report stock raises after it.
        case ending
    }

    enum Outcome: Equatable, Sendable {
        case pasted, copied, noSpeech, pastedRaw, copiedRaw, pasteFailed, partLost, failed
        case noCleanupModel(copies: Bool)
    }

    static let barCount = 4
    static let steps = 8
    /// Stock's sentences, read as text because stock reports them only through `showMessage`.
    static let noSpeech = String(localized: "No speech was recorded")
    static let pasteFailed = String(localized: "Couldn't paste dictation into this app")
    static let partLost = String(localized: "Couldn't paste some dictation into this app")

    static let missingCleanupModel = String(
        localized: "Cleanup has no model, so the raw text was pasted", table: "Notchcast")

    private(set) var phase = Phase.idle
    private(set) var display: UInt32?
    private(set) var copies = false
    /// Each bar's step, 0..<steps, so a level that moves within a step reposts nothing.
    private(set) var bars = Array(repeating: 0, count: barCount)
    private(set) var seconds = 0
    private(set) var raw = false
    private(set) var reached = false
    private(set) var outcome: Outcome?
    private(set) var holdsKeys = false
    /// Bumped by every `begin`, so a settle meant for an older session does nothing.
    private(set) var generation = 0
    private var started: TimeInterval = 0
    private var cleanupModelMissing = false

    var isLive: Bool { phase != .idle }
    var meter: [Double] { bars.map { Double($0) / Double(Self.steps - 1) } }
    var elapsed: String { Self.clock(seconds) }

    static func clock(_ seconds: Int) -> String {
        let second = seconds % 60
        return "\(seconds / 60):\(second < 10 ? "0" : "")\(second)"
    }

    mutating func begin(copies: Bool, at now: TimeInterval) {
        let next = generation &+ 1
        self = DictationIslandSession()
        generation = next
        phase = .recording
        self.copies = copies
        started = now
        holdsKeys = true
    }

    mutating func place(on display: UInt32?) -> Bool {
        switch phase {
        case .recording, .transcribing, .cleaningUp:
            guard self.display != display else { return false }
            self.display = display
            return true
        case .idle, .ending:
            return false
        }
    }

    /// True only when a bar's step or the elapsed second changed, so silence reposts once a second.
    mutating func hear(levels: [Float], at now: TimeInterval) -> Bool {
        guard phase == .recording else { return false }
        let steps = IslandNotice.bars(levels.map(Double.init), count: Self.barCount, floor: 0)
            .map { min(Self.steps - 1, Int($0 * Double(Self.steps))) }
        let second = max(0, Int(now - started))
        guard steps != bars || second != seconds else { return false }
        bars = steps
        seconds = second
        return true
    }

    mutating func transcribe() -> Bool {
        guard phase == .recording else { return false }
        phase = .transcribing
        return true
    }

    mutating func cleanUp() -> Bool {
        guard phase == .transcribing else { return false }
        phase = .cleaningUp
        return true
    }

    /// True when the island reports the raw paste, so the caller drops the stock sentence.
    mutating func cleanupFailed(covered: Bool) -> Bool {
        guard phase == .cleaningUp, !covered else { return false }
        raw = true
        return true
    }

    mutating func delivered(empty: Bool) {
        guard isLive else { return }
        reached = !empty
        holdsKeys = false
    }

    /// True when the island takes stock's report; any other text still shows as stock wrote it.
    mutating func message(_ text: String, covered: Bool) -> Bool {
        guard isLive, !covered else { return false }
        switch text {
        case DictationIslandSession.noSpeech: outcome = .noSpeech
        case DictationIslandSession.pasteFailed: outcome = .pasteFailed
        case DictationIslandSession.partLost: outcome = .partLost
        case DictationIslandSession.missingCleanupModel:
            guard phase == .cleaningUp else { return false }
            cleanupModelMissing = true
        default:
            outcome = .failed
            return false
        }
        return true
    }

    /// True when this end starts the settle hop; a repeat while ending starts none.
    @discardableResult
    mutating func end(completed: Bool) -> Bool {
        guard isLive, !(completed && phase == .ending) else { return false }
        holdsKeys = false
        guard completed else {
            reset()
            return false
        }
        phase = .ending
        return true
    }

    /// Preserve the missing-model result when covered so the coordinator can show its HUD.
    mutating func settle(generation: Int, covered: Bool) -> Outcome? {
        guard generation == self.generation, phase == .ending else { return nil }
        let delivery: Outcome = raw ? (copies ? .copiedRaw : .pastedRaw) : (copies ? .copied : .pasted)
        let result = outcome ?? (reached ? (cleanupModelMissing ? .noCleanupModel(copies: copies) : delivery) : .noSpeech)
        reset()
        if case .noCleanupModel = result { return result }
        return covered ? nil : result
    }

    private mutating func reset() {
        let (generation, display) = (generation, display)
        self = DictationIslandSession()
        self.generation = generation
        self.display = display
    }
}
