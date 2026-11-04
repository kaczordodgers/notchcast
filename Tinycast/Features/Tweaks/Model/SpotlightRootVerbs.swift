import Foundation

nonisolated enum SpotlightRootVerbs: String, Sendable {
    case turnOffIndexing = "spotlight-off"

    var executable: String { "/usr/bin/mdutil" }
    var arguments: [String] { ["-a", "-i", "off"] }
    var timeout: TimeInterval { 10 }
    var environment: [String: String] { [:] }
}
