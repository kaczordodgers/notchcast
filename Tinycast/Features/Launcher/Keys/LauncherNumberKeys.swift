enum LauncherNumberKeys {
    static func entryIndex(digit: Int, query: String, entryCount: Int, enabled: Bool) -> Int? {
        guard enabled, !query.isEmpty, (1...9).contains(digit), digit <= entryCount else {
            return nil
        }
        return digit - 1
    }
}
