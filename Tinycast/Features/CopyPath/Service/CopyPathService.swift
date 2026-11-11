import Foundation

struct CopyPathService: Sendable {
    enum Failure: LocalizedError, Equatable {
        case needsAutomation
        case needsAccessibility
        case timedOut
        case unreadable

        var errorDescription: String? {
            switch self {
            case .needsAutomation: String(localized: "Allow Automation access to copy the path.", table: "Notchcast")
            case .needsAccessibility: String(localized: "Allow Accessibility access to copy the path.", table: "Notchcast")
            case .timedOut: String(localized: "The app did not respond in time.", table: "Notchcast")
            case .unreadable: String(localized: "Could not read the path.", table: "Notchcast")
            }
        }

        static func appleEvent(_ code: Int) -> Self {
            switch code {
            case -1743: .needsAutomation
            case -1712: .timedOut
            default: .unreadable
            }
        }
    }

    enum Request: Equatable, Sendable {
        case finderSelection
        case finderFolder
        case browser(CopyPathTarget)
        case document(CopyPathTarget)
    }

    typealias Read = @Sendable (Request) async throws -> [String]
    private let read: Read

    init(read: @escaping Read = CopyPathSystemReader.read) {
        self.read = read
    }

    func resolve(target: CopyPathTarget?, home: String) async throws -> CopyPathEngine.Outcome {
        try Task.checkCancellation()
        guard let target else { return .nothing }
        if target.bundleID == "com.apple.finder" {
            var paths = try await read(.finderSelection)
            try Task.checkCancellation()
            if paths.isEmpty { paths = try await read(.finderFolder) }
            try Task.checkCancellation()
            return CopyPathEngine.paths(paths, home: home)
        }
        if target.browser != nil {
            let addresses = try await read(.browser(target))
            try Task.checkCancellation()
            if let address = addresses.first, let link = WebRules.cleanLink(address) {
                return .link(link)
            }
        }
        let documents = try await read(.document(target))
        try Task.checkCancellation()
        return CopyPathEngine.document(documents.first, home: home)
    }
}
