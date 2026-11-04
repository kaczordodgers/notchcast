import Foundation

enum MachineBackupPolicy {
    static func runNow(_ configuration: MachineBackupConfiguration) throws -> MachineBackupRequest {
        try configuration.validate()
        return MachineBackupRequest(executable: URL(fileURLWithPath: "/bin/launchctl"), arguments: [
            "kickstart", "gui/\(configuration.userID)/\(configuration.jobLabel)",
        ])
    }

    static func snapshots(_ configuration: MachineBackupConfiguration) throws -> MachineBackupRequest {
        try restic(configuration, arguments: ["snapshots", "--host", configuration.host, "--json"])
    }

    static func browse(_ configuration: MachineBackupConfiguration, snapshot: String,
                       path: String) throws -> MachineBackupRequest {
        try validateSnapshot(snapshot)
        try validatePath(path)
        return try restic(configuration, arguments: ["ls", snapshot, path, "--json"])
    }

    static func restore(_ configuration: MachineBackupConfiguration, snapshot: String,
                        path: String, target: URL) throws -> MachineBackupRequest {
        try validateSnapshot(snapshot)
        try validatePath(path)
        let home = configuration.homeDirectory.standardizedFileURL.path
        guard path.hasPrefix(home + "/"),
              !path.contains(where: { "*?[]\\".contains($0) }) else { throw MachineBackupFailure.invalidPath }
        try validateTarget(target, home: configuration.homeDirectory)
        var request = try restic(configuration, arguments: [
            "restore", snapshot, "--include", path, "--target", target.path, "--overwrite", "never",
        ])
        request.restoreTarget = target
        request.homeDirectory = configuration.homeDirectory
        return request
    }

    static func validateTarget(_ target: URL, home: URL) throws {
        let downloads = home.standardizedFileURL.appendingPathComponent("Downloads", isDirectory: true)
        guard target.isFileURL, target.path == target.standardizedFileURL.path,
              target.deletingLastPathComponent().standardizedFileURL == downloads,
              !target.lastPathComponent.isEmpty,
              !target.lastPathComponent.hasPrefix("."),
              !isSystemPath(target.path), !isSystemPath(home.path) else {
            throw MachineBackupFailure.unsafeTarget
        }
    }

    static func decodeSnapshots(_ data: Data, host: String) throws -> [MachineBackupSnapshot] {
        do {
            let values = try JSONDecoder().decode([MachineBackupSnapshot].self, from: data)
            let dated = try values.map { value in
                try validateSnapshot(value.id)
                let date: Date
                if let fractional = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value.time) {
                    date = fractional
                } else {
                    date = try Date.ISO8601FormatStyle().parse(value.time)
                }
                return (snapshot: value, date: date)
            }
            return dated.filter { $0.snapshot.hostname == host }
                .sorted { $0.date == $1.date ? $0.snapshot.id < $1.snapshot.id : $0.date > $1.date }
                .map(\.snapshot)
        } catch { throw MachineBackupFailure.invalidResponse }
    }

    static func decodeNodes(_ data: Data) throws -> [MachineBackupNode] {
        do {
            return try data.split(separator: 10).compactMap { line in
                let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                guard let object else { throw MachineBackupFailure.invalidResponse }
                if object["struct_type"] as? String == "snapshot" { return nil }
                guard object["struct_type"] as? String == "node" else { throw MachineBackupFailure.invalidResponse }
                return try JSONDecoder().decode(MachineBackupNode.self, from: Data(line))
            }
        } catch { throw MachineBackupFailure.invalidResponse }
    }

    private static func restic(_ configuration: MachineBackupConfiguration,
                               arguments: [String]) throws -> MachineBackupRequest {
        try configuration.validate()
        return MachineBackupRequest(executable: configuration.resticExecutable, arguments: ["--no-cache"] + arguments,
                                    environment: ["RESTIC_REPOSITORY": configuration.repository,
                                                  "RESTIC_PASSWORD_COMMAND": configuration.passwordCommand,
                                                  "HOME": configuration.homeDirectory.path])
    }

    private static func validateSnapshot(_ snapshot: String) throws {
        guard snapshot.count == 64, snapshot.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw MachineBackupFailure.invalidSnapshot
        }
    }

    private static func validatePath(_ path: String) throws {
        guard path.hasPrefix("/"), !path.utf8.contains(0),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw MachineBackupFailure.invalidPath
        }
    }

    private static func isSystemPath(_ path: String) -> Bool {
        let roots = ["/System", "/Library", "/Applications", "/bin", "/sbin", "/usr", "/etc", "/var", "/dev",
                     "/private/etc", "/private/var"]
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
