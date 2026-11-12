import Foundation

nonisolated enum MagpieGateway {
    static let defaultAddress = "http://127.0.0.1:3425"

    static func url(_ address: String) -> URL? {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme),
              let host = url.host(), !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}
