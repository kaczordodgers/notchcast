import Foundation

enum GreenMaximizeClick {
    static func intercept(
        point: CGPoint, rect: CGRect?, age: TimeInterval, option: Bool,
        bundleID: String?, exclusions: Set<String>
    ) -> Bool {
        guard !option, age >= 0, age < 2, let rect, !rect.isEmpty,
            let bundleID, !exclusions.contains(bundleID)
        else { return false }
        return rect.contains(point)
    }
}
