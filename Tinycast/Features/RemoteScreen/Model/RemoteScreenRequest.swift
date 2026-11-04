import Foundation
import Darwin

struct RemoteScreenRequest: Codable, Equatable, Sendable {
    let host: String

    func validatedURL() throws -> URL {
        guard validHost else { throw Failure.invalidHost }
        var components = URLComponents()
        components.scheme = "vnc"
        components.host = host.contains(":") ? "[\(host)]" : host
        guard let url = components.url, url.host != nil else { throw Failure.invalidHost }
        return url
    }

    private var validHost: Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        if host.contains(":") {
            var address = in6_addr()
            return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1
        }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-")
                && !label.hasSuffix("-") && label.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    enum Failure: Error { case invalidHost, unavailable, invalidResponse }
}
