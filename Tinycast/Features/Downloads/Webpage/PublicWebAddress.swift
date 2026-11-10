import Darwin
import Foundation

enum PublicWebAddress {
    enum Refusal: LocalizedError {
        case invalidURL, privateAddress, resolutionFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                String(localized: "Enter a public HTTP or HTTPS webpage URL without credentials, using port 80 or 443.", table: "Notchcast")
            case .privateAddress:
                String(localized: "Private and loopback addresses cannot be saved as webpages.", table: "Notchcast")
            case .resolutionFailed:
                String(localized: "The webpage host could not be resolved to a public address.", table: "Notchcast")
            }
        }
    }

    static func validate(_ url: URL) throws {
        guard WebRules.isWebScheme(url.scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.port == nil || url.port == 80 || url.port == 443 else { throw Refusal.invalidURL }
        let name = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !name.isEmpty, name != "localhost", !name.hasSuffix(".localhost"), !name.hasSuffix(".local"),
              name.contains(".") || name.contains(":"), !name.contains("%") else { throw Refusal.privateAddress }
        if isNumeric(name) {
            guard isPublicIP(name), !name.split(separator: ".").contains(where: {
                $0.count > 1 && $0.hasPrefix("0")
            }) else { throw Refusal.privateAddress }
        }
    }

    static func isPublicIP(_ text: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, text, &ipv4) == 1 {
            let value = UInt32(bigEndian: ipv4.s_addr)
            let excluded: [(UInt32, UInt32)] = [
                (0x00000000, 8), (0x0a000000, 8), (0x64400000, 10), (0x7f000000, 8),
                (0xa9fe0000, 16), (0xac100000, 12), (0xc0000000, 24), (0xc0000200, 24),
                (0xc0586300, 24), (0xc0a80000, 16), (0xc6120000, 15), (0xc6336400, 24),
                (0xcb007100, 24), (0xe0000000, 3)
            ]
            return !excluded.contains { network, bits in value >> (32 - bits) == network >> (32 - bits) }
        }
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, text, &ipv6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
        // Only global unicast; transition mechanisms can conceal a non-public IPv4 endpoint.
        guard bytes[0] & 0xe0 == 0x20, !(bytes[0] == 0x20 && bytes[1] == 0x02) else { return false }
        if bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] & 0xf0 == 0 { return false }
        if bytes[0] == 0x20 && bytes[1] == 0x01 {
            if bytes[2] < 2 || (bytes[2] == 0x0d && bytes[3] == 0xb8) { return false }
        }
        return true
    }

    @concurrent
    static func resolve(_ host: String, port: UInt16) async throws -> [String] {
        try Task.checkCancellation()
        let name = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        try validate(URL(string: "http://\(name.contains(":") ? "[\(name)]" : name):\(port)/") ?? URL(filePath: "/"))
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, String(port), &hints, &result) == 0, let first = result else { throw Refusal.resolutionFailed }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen,
                              &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else {
                throw Refusal.resolutionFailed
            }
            guard let address = String(bytes: buffer.prefix(while: { $0 != 0 }).map({ UInt8(bitPattern: $0) }),
                                       encoding: .utf8) else { throw Refusal.resolutionFailed }
            guard isPublicIP(address) else { throw Refusal.privateAddress }
            if !addresses.contains(address) { addresses.append(address) }
            current = entry.pointee.ai_next
        }
        try Task.checkCancellation()
        guard !addresses.isEmpty else { throw Refusal.resolutionFailed }
        return addresses
    }

    private static func isNumeric(_ host: String) -> Bool {
        host.contains(":") || host.allSatisfy { $0.isNumber || $0 == "." }
            || host.hasPrefix("0x") || host.split(separator: ".").contains(where: { $0.hasPrefix("0x") })
    }
}
