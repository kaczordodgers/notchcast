import Foundation

enum AppUpdateVersion {
    static func compare(_ left: String, _ right: String) -> ComparisonResult? {
        func parts(_ value: String) -> [UInt64]? {
            let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
            guard !pieces.isEmpty else { return nil }
            var result: [UInt64] = []
            for piece in pieces {
                guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let number = UInt64(piece) else { return nil }
                result.append(number)
            }
            return result
        }
        guard let lhs = parts(left), let rhs = parts(right) else { return nil }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
