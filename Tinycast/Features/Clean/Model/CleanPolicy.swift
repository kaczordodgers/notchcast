import Foundation

struct CleanPolicy: Sendable {
    let home: URL
    let now: Date
    let logAge: TimeInterval
    let installerAge: TimeInterval
    let installedBundleIDs: Set<String>
    let protectedNames: Set<String>

    func permits(_ path: String, category: CleanCategory) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("."), !components.contains(".."), category != .trash else {
            return false
        }
        let root = home.appendingPathComponent(category.relativeRoot).standardizedFileURL.path
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized.hasPrefix(root + "/") else { return false }
        let names = standardized.dropFirst(root.count + 1).split(separator: "/").map(String.init)
        return names.allSatisfy {
            !$0.hasPrefix(".") && !$0.lowercased().hasPrefix("com.apple.")
                && !$0.lowercased().hasPrefix("apple") && !protectedNames.contains($0)
        }
    }

    func eligible(_ url: URL, category: CleanCategory, newest: Date) -> Bool {
        guard permits(url.path, category: category) else { return false }
        switch category {
        case .logs: return now.timeIntervalSince(newest) > max(0, logAge)
        case .installers:
            return url.lastPathComponent.hasPrefix("Install macOS ") && url.pathExtension == "app"
                && now.timeIntervalSince(newest) > max(0, installerAge)
        case .firmware:
            return url.pathExtension == "ipsw"
                && now.timeIntervalSince(newest) > max(0, installerAge)
        case .leftovers:
            let name = url.lastPathComponent
            return name.split(separator: ".").count >= 3 && !installedBundleIDs.contains(name)
        default: return true
        }
    }
}
