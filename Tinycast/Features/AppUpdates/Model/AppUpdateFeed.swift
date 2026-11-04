import Foundation

enum AppUpdateFeed {
    static let limit = 2_000_000
    static func caskApplications(_ data: Data?) -> [String: String] {
        guard let data, data.count <= limit,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for row in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = row["token"] as? String else { continue }
            for artifact in row["artifacts"] as? [[String: Any]] ?? [] {
                for app in artifact["app"] as? [String] ?? [] where app.hasSuffix(".app") {
                    result[URL(filePath: app).lastPathComponent] = token
                }
            }
        }
        return result
    }

    static func releases(_ data: Data) throws -> [(version: String, build: String)] {
        guard data.count <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        guard let text = String(data: data, encoding: .utf8)?.uppercased(),
              !text.contains("<!DOCTYPE"), !text.contains("<!ENTITY") else {
            throw URLError(.cannotParseResponse)
        }
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.rss else { throw URLError(.cannotParseResponse) }
        return reader.releases
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var releases: [(version: String, build: String)] = []
        var rss = false
        var inItem = false
        var candidate: (version: String, build: String)?
        var excluded = false
        var text = ""
        var build: String?
        var version: String?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            text = ""
            if name == "rss" { rss = true }
            if name == "item" {
                inItem = true; excluded = false; candidate = nil; build = nil; version = nil
            }
            if name == "sparkle:deltas" { excluded = true }
            if name == "enclosure", inItem {
                guard attributes["sparkle:deltaFrom"] == nil,
                      attributes["sparkle:os"].map({ ["macos", "osx"].contains($0) }) != false
                else { excluded = true; return }
                build = attributes["sparkle:version"] ?? build
                version = attributes["sparkle:shortVersionString"] ?? version
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if inItem, name == "sparkle:version" { build = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if inItem, name == "sparkle:shortVersionString" {
                version = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if ["sparkle:channel", "sparkle:maximumSystemVersion",
                "sparkle:hardwareRequirements"].contains(name) { excluded = true }
            if name == "item" {
                if let build { candidate = (version ?? build, build) }
                if !excluded, let candidate { releases.append(candidate) }
                inItem = false
            }
        }
    }
}
