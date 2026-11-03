import Foundation

struct SoloistBuild: Equatable, Sendable {
    static let lifetime: TimeInterval = 90 * 86_400

    let executable: URL
    let version: String
    let built: Date

    var expires: Date { built.addingTimeInterval(Self.lifetime) }

    func daysRemaining(at now: Date) -> Int {
        max(0, Int(ceil(expires.timeIntervalSince(now) / 86_400)))
    }

    static func parseVersion(_ output: String) -> (version: String, built: Date)? {
        let words = output.split(whereSeparator: \.isWhitespace)
        guard let start = words.firstIndex(of: "soloist"), words.count > start + 3,
              words[start + 2] == "build", let epoch = TimeInterval(words[start + 3]),
              epoch.isFinite, epoch > 0 else { return nil }
        return (String(words[start + 1]), Date(timeIntervalSince1970: epoch))
    }

    static func isUsable(built: Date, now: Date) -> Bool {
        built <= now.addingTimeInterval(86_400) && now < built.addingTimeInterval(lifetime)
    }
}
