enum LauncherNumberKeys {
    static func badgeSlot(entryIndex index: Int, query: String, enabled: Bool) -> Character? {
        let digit = index + 1
        guard index >= 0,
              entryIndex(digit: digit, query: query, entryCount: digit, enabled: enabled) == index else {
            return nil
        }
        return Character(String(digit))
    }

    static func rowIndex(
        digit: Int, query: String, entryRows: [Int], favoriteCount: Int,
        hasLeadCard: Bool, enabled: Bool
    ) -> Int? {
        if let index = entryIndex(digit: digit, query: query, entryCount: entryRows.count, enabled: enabled) {
            return entryRows[index]
        }
        guard digit > 0, digit <= favoriteCount else { return nil }
        return digit - 1 + (hasLeadCard ? 1 : 0)
    }

    static func entryIndex(digit: Int, query: String, entryCount: Int, enabled: Bool) -> Int? {
        guard enabled, !query.isEmpty, (1...9).contains(digit), digit <= entryCount else {
            return nil
        }
        return digit - 1
    }
}
