import Foundation

struct MachSSH: Sendable {
    struct Result: Sendable {
        let status: Int32
        let output: String
        var message: String? {
            status == 255 ? String(localized: "Unable to reach the remote Mac over SSH") : nil
        }
    }

    enum Route: Sendable { case thunderbolt, tailscale }
    typealias Runner = @Sendable (String, [String]) async throws -> Result
    static let options = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                          "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3"]
    let address: String
    let runner: Runner

    init(address: String = "mbp", runner: @escaping Runner) {
        self.address = Self.isValid(address) ? address : "mbp"
        self.runner = runner
    }

    static func isValid(_ address: String) -> Bool {
        !address.isEmpty && !address.hasPrefix("-") &&
            address.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._-@:".unicodeScalars.contains($0) }
    }

    func run(_ command: String) async throws -> Result {
        try await runner("/usr/bin/ssh", Self.options + [address, command])
    }

    func route(thunderboltAddress: String) async throws -> Route {
        let result = try await runner("/usr/bin/ssh", ["-G", address])
        guard result.status == 0 else { throw RouteError.unavailable }
        let hostname = result.output.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count == 2 && fields[0].lowercased() == "hostname" ? String(fields[1]) : nil
        }.first
        guard let hostname else { throw RouteError.unavailable }
        return hostname == thunderboltAddress ? .thunderbolt : .tailscale
    }

    enum RouteError: Error { case unavailable }

    var terminalScript: String {
        let command = (["/usr/bin/ssh", "-t"] + Self.options +
            [address, "cd \"$HOME/chad\" && exec /bin/zsh -l"]).map(Self.quote).joined(separator: " ")
        return command + "; status=$?; if [ \"$status\" -eq 255 ]; then printf '%s\\n' " +
            Self.quote(String(localized: "Unable to reach the remote Mac over SSH")) +
            "; fi; exec /bin/zsh -l"
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
