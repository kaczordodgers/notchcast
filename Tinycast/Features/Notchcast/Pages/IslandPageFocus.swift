import Foundation

/// Where the keyboard is on an open page: the header's ring, else the list's selected row.
enum IslandPageFocus {
    /// The header's slots are the pages, then Pin, then Settings.
    static let headerCount = IslandPage.allCases.count + 2

    /// The first move starts from the page on show, so ← and → step to its neighbours, as tabs do.
    static func header(after focus: Int?, shown: IslandPage, delta: Int) -> Int {
        let start = focus ?? IslandPage.allCases.firstIndex(of: shown) ?? 0
        return ((start + delta) % headerCount + headerCount) % headerCount
    }

    /// A selection whose row has gone falls back to the first row, as the launcher's does.
    static func selection<ID: Equatable>(in ids: [ID], stored: ID?) -> ID? {
        ids.first { $0 == stored } ?? ids.first
    }

    static func row<ID: Equatable>(in ids: [ID], from stored: ID?, by delta: Int) -> ID? {
        guard !ids.isEmpty else { return nil }
        let index = selection(in: ids, stored: stored).flatMap(ids.firstIndex(of:)) ?? 0
        return ids[max(0, min(ids.count - 1, index + delta))]
    }
}
