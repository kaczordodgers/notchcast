import Foundation

struct CleanPurgePolicy: Sendable {
    let projectRoots: [URL]
    let now: Date
    let recentActivityThreshold: TimeInterval
    let maximumDepth: Int
    let maximumEntries: Int
    let protectedNames: Set<String>

    func permits(_ url: URL) -> Bool {
        guard !url.pathComponents.contains(".."), !url.pathComponents.contains("."),
              !url.pathComponents.contains(where: protectedNames.contains) else { return false }
        return projectRoots.contains {
            url.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path + "/")
        }
    }
}
