import Darwin
import Foundation

nonisolated struct ArchiveCompressor: Sendable {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser
    var run: @Sendable (URL, [String]) async throws -> Int32 = { tool, arguments in
        try await ArchiveProcess.run(tool: tool, arguments: arguments).status
    }

    @concurrent func compress(_ sources: [URL], format: ArchiveCompression) async throws -> URL {
        let files = FileManager.default
        guard !sources.isEmpty, sources.allSatisfy({ $0.isFileURL && files.fileExists(atPath: $0.path) }) else {
            throw ArchiveFailure.filesystem("selection")
        }
        let output = format.output(sources: sources) { files.fileExists(atPath: $0.path) }
        let temporary = output.deletingLastPathComponent().appending(path: ".\(UUID()).\(format.suffix)")
        defer { if files.fileExists(atPath: temporary.path) { try? files.removeItem(at: temporary) } }
        let tool: URL
        var inputs = sources
        let staging = output.deletingLastPathComponent().appending(path: ".\(UUID())")
        defer { if files.fileExists(atPath: staging.path) { try? files.removeItem(at: staging) } }
        if format == .zip, sources.count > 1 {
            try files.createDirectory(at: staging, withIntermediateDirectories: false)
            for source in sources {
                try Task.checkCancellation()
                try files.copyItem(at: source, to: staging.appending(path: source.lastPathComponent))
            }
            inputs = [staging]
        }
        var zstd: URL?
        switch format {
        case .zip: tool = URL(filePath: "/usr/bin/ditto")
        case .small: tool = try locate("7zz", install: "brew install sevenzip")
        case .fast:
            tool = URL(filePath: "/usr/bin/tar")
            zstd = try locate("zstd", install: "brew install zstd")
        }
        var arguments = format.arguments(sources: inputs, output: temporary, zstd: zstd)
        if format == .zip, sources.count > 1 { arguments.removeAll { $0 == "--keepParent" } }
        let status = try await run(tool, arguments)
        guard status == 0 else { throw ArchiveFailure.compressionFailed(status) }
        try Task.checkCancellation()
        guard renamex_np(temporary.path, output.path, UInt32(RENAME_EXCL)) == 0 else {
            throw ArchiveFailure.filesystem("publish")
        }
        return output
    }

    private func locate(_ name: String, install: String) throws -> URL {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        guard let tool = paths.filter({ $0.hasPrefix("/") }).map({ URL(filePath: $0).appending(path: name) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ArchiveFailure.compressionToolMissing(install)
        }
        return tool
    }
}
