import Darwin
import Foundation

nonisolated struct NetworkPublicIPService: Sendable {
    @concurrent
    func lookup() async -> String? {
        let configuration = NotchcastIdentity.sessionConfiguration()
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let url = URL(string: "https://1.1.1.1/cdn-cgi/trace")!
            let (data, response) = try await session.data(from: url)
            guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                  let trace = String(data: data, encoding: .utf8) else { return nil }
            return Self.parse(trace)
        } catch { return nil }
    }

    static func parse(_ trace: String) -> String? {
        guard let line = trace.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("ip=") }) else {
            return nil
        }
        let address = String(line.dropFirst(3))
        var storage = in6_addr()
        guard inet_pton(AF_INET, address, &storage) == 1 || inet_pton(AF_INET6, address, &storage) == 1 else {
            return nil
        }
        return address
    }
}
