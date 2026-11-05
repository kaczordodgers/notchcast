enum DictationHistoryClearPolicy {
    static func isEnabled(isLoading: Bool, isClearing: Bool, isEmpty: Bool, loadFailed: Bool) -> Bool {
        !isLoading && !isClearing && (!isEmpty || loadFailed)
    }
}
