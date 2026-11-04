import Foundation

struct AppUpdate: Sendable, Equatable {
    struct App: Sendable, Equatable {
        let id: String
        let version: String
        let build: String
        var appStore = false
        var feed: URL?
        var cask: String?
    }

    enum Source: Sendable { case appStore, sparkle, homebrew }
    let app: App
    let source: Source?
    let latest: String?
    let link: URL?
    let isNewer: Bool?
}
