import Foundation

enum GreenMaximizeClick {
    static func target<T>(point: CGPoint, candidates: [T], rect: (T) -> CGRect) -> T? {
        candidates.first { rect($0).contains(point) }
    }
    static func intercept(
        point: CGPoint, rect: CGRect?, age: TimeInterval, option: Bool,
        bundleID: String?, exclusions: Set<String>, verified: Bool = true
    ) -> Bool {
        guard verified, !option, age >= 0, age < 2, let rect, !rect.isEmpty,
            let bundleID, !exclusions.contains(bundleID)
        else { return false }
        return rect.contains(point)
    }
}
