enum SpacesOrderEngine {
    enum Value: String, Sendable, CaseIterable {
        case absent, enabled, disabled
    }

    static func target(enabled: Bool, original: Value?) -> Value? {
        enabled ? .disabled : original
    }

    static func needsWrite(current: Value, target: Value?) -> Bool {
        target != nil && current != target
    }
}
