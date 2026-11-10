import Foundation

enum CopyPathEngine {
    enum Outcome: Equatable, Sendable {
        case path(String)
        case link(String)
        case nothing
    }

    static func paths(_ paths: [String], home: String) -> Outcome {
        let text = paths.filter { $0.hasPrefix("/") }.map { display($0, home: home) }
        return text.isEmpty ? .nothing : .path(text.joined(separator: "\n"))
    }

    static func document(_ address: String?, home: String) -> Outcome {
        guard let address, !address.isEmpty else { return .nothing }
        if address.hasPrefix("/") { return paths([address], home: home) }
        if let url = URL(string: address), url.isFileURL, url.host == nil || url.host == "localhost" {
            return paths([url.path(percentEncoded: false)], home: home)
        }
        return NotchcastLink.clean(address).map(Outcome.link) ?? .nothing
    }

    private static func display(_ raw: String, home: String) -> String {
        var path = raw
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
