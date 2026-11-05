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

    var limitUndo: String? {
        guard let priorLimit else { return "charge-limit-off" }
        guard [60, 70, 80, 90].contains(priorLimit) else { return nil }
        return "charge-limit-\(priorLimit)"
    }

    mutating func reapplyLimit() {
        guard var effect = effects["charge-limit"], effect.intent == nil else { return }
        effect.intent = effect.applied
        effect.applied = nil
        effects["charge-limit"] = effect
    }

    mutating func adopt(_ key: String, applied: String?, undo: String) {
        guard effects[key] == nil else { return }
        effects[key] = Effect(applied: applied, intent: applied, undo: undo)
    }

    func canRun(_ key: String, verb: String, now: Date, releasing: Bool) -> Bool {
        guard let effect = effects[key] else { return !releasing }
        if !releasing && effect.applied == verb && effect.intent == nil { return false }
        if effect.intent != verb { return true }
        return effect.attempts < 6 && (effect.retryAt.map { now >= $0 } ?? true)
    }

    mutating func begin(_ key: String, verb: String, undo: String) {
        var effect = effects[key] ?? Effect(undo: undo)
        if effect.intent != verb {
            effect.attempts = 0
            effect.retryAt = nil
            effect.failed = false
        }
        effect.intent = verb
        effects[key] = effect
    }

    mutating func succeed(_ key: String, verb: String, releasing: Bool) {
        guard var effect = effects[key], effect.intent == verb else { return }
        if releasing { release(key); return }
        effect.applied = verb
        effect.intent = nil
        effect.failed = false
        effect.attempts = 0
        effect.retryAt = nil
        effects[key] = effect
    }

    mutating func fail(_ key: String, now: Date) {
        guard var effect = effects[key] else { return }
        effect.failed = true
        effect.attempts += 1
        effect.retryAt = now.addingTimeInterval(60 * pow(2, Double(effect.attempts - 1)))
        effects[key] = effect
    }

    mutating func release(_ key: String) {
        effects[key] = nil
        if key == "charge-limit" { capturedLimit = false; priorLimit = nil }
    }

    func userChangedLimit(_ current: Int?) -> Bool {
        guard let effect = effects["charge-limit"] else { return false }
        let value = current.map { "charge-limit-\($0)" } ?? "charge-limit-off"
        return value != effect.applied && value != effect.intent
    }
}
