import Foundation

struct BatteryOwnershipJournal: Codable, Sendable, Equatable {
    struct Effect: Codable, Sendable, Equatable {
        var applied: String?
        var intent: String?
        var undo: String
        var attempts = 0
        var retryAt: Date?
        var failed = false
    }

    private(set) var effects: [String: Effect] = [:]
    private(set) var priorLimit: Int?
    private(set) var capturedLimit = false

    mutating func captureLimit(_ limit: Int?) {
        guard !capturedLimit else { return }
        priorLimit = limit
        capturedLimit = true
    }

    var limitUndo: String? { RootContract.Command(chargeLimit: priorLimit)?.rawValue }

    mutating func reapplyLimit() {
        guard var effect = effects[Key.chargeLimit.rawValue], effect.intent == nil else { return }
        effect.intent = effect.applied
        effect.applied = nil
        effects[Key.chargeLimit.rawValue] = effect
    }

    mutating func adopt(_ key: Key, applied: String?, undo: String) {
        guard effects[key.rawValue] == nil else { return }
        effects[key.rawValue] = Effect(applied: applied, intent: applied, undo: undo)
    }

    func canRun(_ key: Key, verb: String, now: Date, releasing: Bool) -> Bool {
        guard let effect = effects[key.rawValue] else { return !releasing }
        if !releasing && effect.applied == verb && effect.intent == nil { return false }
        if effect.intent != verb { return true }
        return effect.attempts < 6 && (effect.retryAt.map { now >= $0 } ?? true)
    }

    mutating func begin(_ key: Key, verb: String, undo: String) {
        var effect = effects[key.rawValue] ?? Effect(undo: undo)
        if effect.intent != verb {
            effect.attempts = 0
            effect.retryAt = nil
            effect.failed = false
        }
        effect.intent = verb
        effects[key.rawValue] = effect
    }

    mutating func succeed(_ key: Key, verb: String, releasing: Bool) {
        guard var effect = effects[key.rawValue], effect.intent == verb else { return }
        if releasing { release(key); return }
        effect.applied = verb
        effect.intent = nil
        effect.failed = false
        effect.attempts = 0
        effect.retryAt = nil
        effects[key.rawValue] = effect
    }

    mutating func fail(_ key: Key, now: Date) {
        guard var effect = effects[key.rawValue] else { return }
        effect.failed = true
        effect.attempts += 1
        effect.retryAt = now.addingTimeInterval(60 * pow(2, Double(effect.attempts - 1)))
        effects[key.rawValue] = effect
    }

    mutating func release(_ key: Key) {
        effects[key.rawValue] = nil
        if key == .chargeLimit { capturedLimit = false; priorLimit = nil }
    }

    func userChangedLimit(_ current: Int?) -> Bool {
        guard let effect = effects[Key.chargeLimit.rawValue] else { return false }
        guard let value = RootContract.Command(chargeLimit: current)?.rawValue else { return true }
        return value != effect.applied && value != effect.intent
    }
}
