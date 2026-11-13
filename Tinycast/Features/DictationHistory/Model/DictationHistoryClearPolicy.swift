enum DictationHistoryClearPolicy {
    static func isEnabled(isLoading: Bool, isClearing: Bool, isEmpty: Bool, hasQuarantine: Bool, loadFailed: Bool) -> Bool {
        !isLoading && !isClearing && (!isEmpty || hasQuarantine || loadFailed)
    }
}
