import Foundation
import Observation

@MainActor
protocol URLCleanerPasteboard: AnyObject {
    var changeCount: Int { get }
    var text: String? { get }
    var isProtected: Bool { get }
    func write(_ text: String) -> Bool
}

@MainActor @Observable
final class URLCleanerModule: NotchcastModule {
    var rules: URLCleanerPolicy.Rules {
        didSet {
            if let data = try? JSONEncoder().encode(rules) { defaults?.set(data, forKey: "urlCleaner.rules") }
        }
    }
    private(set) var lastClean: URLCleanerPolicy.Result?
    private(set) var isRunning = false
    private let defaults: UserDefaults?
    private var lastChangeCount: Int?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        rules = defaults?.data(forKey: "urlCleaner.rules")
            .flatMap { try? JSONDecoder().decode(URLCleanerPolicy.Rules.self, from: $0) } ?? .init()
    }

    func start() { isRunning = true }
    func stop() { isRunning = false; lastChangeCount = nil; lastClean = nil }

    func clipboardDidChange(_ pasteboard: any URLCleanerPasteboard) {
        guard isRunning, pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !pasteboard.isProtected, let text = pasteboard.text else { return }
        let result = URLCleanerPolicy.clean(text, rules: rules)
        guard !result.removed.isEmpty, pasteboard.write(result.text) else { return }
        lastChangeCount = pasteboard.changeCount
        lastClean = result
    }
}
