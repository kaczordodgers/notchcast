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

    init(address: String, runner: @escaping Runner) {
        self.address = address
        self.runner = runner
    }

    static func isValid(_ address: String) -> Bool {
        !address.isEmpty && !address.hasPrefix("-") &&
            address.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-@:".contains($0)) }
    }

    func run(_ command: String) async throws -> Result {
        guard Self.isValid(address) else { throw ConfigurationError.address }
        return try await runner("/usr/bin/ssh", Self.options + [address, command])
    }

    func route(thunderboltAddress: String) async throws -> Route {
        guard Self.isValid(address) else { throw ConfigurationError.address }
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

    func terminalScript(directory: String) throws -> String {
        guard Self.isValid(address) else { throw ConfigurationError.address }
        guard !directory.isEmpty else { throw ConfigurationError.path }
        let command = (["/usr/bin/ssh", "-t"] + Self.options +
            [address, "cd " + Self.remotePath(directory) + " && exec /bin/zsh -l"]).map(Self.quote).joined(separator: " ")
        return command + "; rc=$?; if [ \"$rc\" -eq 255 ]; then printf '%s\\n' " +
            Self.quote(String(localized: "Unable to reach the remote Mac over SSH")) +
            "; fi; exec /bin/zsh -l"
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // Quoting alone would stop the remote shell expanding `~/`.
    static func remotePath(_ value: String) -> String {
        value.hasPrefix("~/") ? "\"$HOME/\"" + quote(String(value.dropFirst(2))) : quote(value)
    }

    enum ConfigurationError: LocalizedError {
        case address, path
        var errorDescription: String? {
            switch self {
            case .address: String(localized: "Set the remote Mac address in Settings")
            case .path: String(localized: "Remote Mac path is not configured.")
            }
        }
    }
}
