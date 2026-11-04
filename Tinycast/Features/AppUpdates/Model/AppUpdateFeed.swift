import Foundation

enum AppUpdateFeed {
    static let limit = 2_000_000

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

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            text = ""
            if name == "rss" { rss = true }
            if name == "item" { inItem = true; excluded = false; candidate = nil }
            if name == "sparkle:deltas" { excluded = true }
            if name == "enclosure", inItem {
                guard attributes["sparkle:deltaFrom"] == nil,
                      attributes["sparkle:os"].map({ ["macos", "osx"].contains($0) }) != false,
                      let build = attributes["sparkle:version"] else { excluded = true; return }
                candidate = (attributes["sparkle:shortVersionString"] ?? build, build)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if ["sparkle:channel", "sparkle:minimumSystemVersion", "sparkle:maximumSystemVersion",
                "sparkle:hardwareRequirements"].contains(name) { excluded = true }
            if name == "item" {
                if !excluded, let candidate { releases.append(candidate) }
                inItem = false
            }
        }
    }
}
