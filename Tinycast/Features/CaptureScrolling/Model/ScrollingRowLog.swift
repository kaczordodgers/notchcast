struct ScrollingRowLog: Sendable {
    private(set) var rows: [UInt64] = []
    private var positions: [UInt64: [Int]] = [:]

    mutating func append(_ hashes: ArraySlice<UInt64>) {
        for hash in hashes {
            positions[hash, default: []].append(rows.count)
            rows.append(hash)
        }
    }

    func placement(of frame: [UInt64], minimumOverlap: Int) -> Int? {
        guard !frame.isEmpty, !rows.isEmpty else { return nil }
        var frequencies: [UInt64: Int] = [:]
        for hash in frame { frequencies[hash, default: 0] += 1 }
        let anchors = frame.indices.filter { frequencies[frame[$0]] == 1 }
        guard !anchors.isEmpty else { return nil }
        var tried = Set<Int>()
        var best: (start: Int, matches: Int)?
        for index in anchors {
            for position in (positions[frame[index]] ?? []).suffix(400) {
                let start = position - index
                guard tried.insert(start).inserted else { continue }
                let first = max(0, -start)
                let last = min(frame.count, rows.count - start)
                let overlap = last - first
                guard overlap >= minimumOverlap else { continue }
                var matches = 0
                for row in first..<last where frame[row] == rows[start + row] { matches += 1 }
                guard matches * 10 >= overlap * 9 else { continue }
                if let previous = best,
                   matches < previous.matches || (matches == previous.matches && start >= previous.start) {
                    continue
                }
                best = (start, matches)
            }
        }
        return best?.start
    }
}
