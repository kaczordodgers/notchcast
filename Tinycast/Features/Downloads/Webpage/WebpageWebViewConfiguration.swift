import Foundation
import Network
import WebKit

@MainActor
enum WebpageWebViewConfiguration {
    static let blockedURLPatterns = [
            #"^https?://([^/@]+@)?\["#,
            #"^https?://([^/@]+@)?[0-9]+(\.[0-9]+)*\.?[:/]"#,
            #"^https?://([^/@]+@)?0x[0-9a-f]+\.?[:/]"#,
            #"^https?://([^/@]+@)?[^/:.]+\.?[:/]"#,
            #"^https?://([^/@]+@)?[^/:]+\.localhost\.?[:/]"#,
            #"^https?://([^/@]+@)?[^/:]+\.local\.?[:/]"#,
            "^wss?://"
        ]

    static func make(proxy: ProxyConfiguration) async throws -> WKWebViewConfiguration {
        let rules: [[String: Any]] = blockedURLPatterns.map {
            ["trigger": ["url-filter": $0], "action": ["type": "block"]]
        }
        let data = try JSONSerialization.data(withJSONObject: rules)
        guard let json = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        let contentRules = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "WebpagePublicAddresses", encodedContentRuleList: json)
        try Task.checkCancellation()
        let configuration = WKWebViewConfiguration()
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.websiteDataStore = .nonPersistent()
        configuration.websiteDataStore.proxyConfigurations = [proxy]
        guard let contentRules else { throw URLError(.cannotLoadFromNetwork) }
        configuration.userContentController.add(contentRules)
        return configuration
    }
}
