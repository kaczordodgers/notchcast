import Foundation
import Network
import WebKit

@MainActor
enum WebpageWebViewConfiguration {
    static func make(proxy: ProxyConfiguration) async throws -> WKWebViewConfiguration {
        let patterns = [
            #"^https?://([^/@]+@)?\["#,
            #"^https?://([^/@]+@)?[0-9][0-9a-fx.]*[:/]"#,
            #"^https?://([^/@]+@)?[^/:.]+\.?[:/]"#,
            #"^https?://([^/@]+@)?[^/:]+\.localhost\.?[:/]"#,
            #"^https?://([^/@]+@)?[^/:]+\.local\.?[:/]"#,
            "^wss?://"
        ]
        let rules: [[String: Any]] = patterns.map {
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
