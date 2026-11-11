import Darwin
import Foundation

nonisolated struct ArchiveCompressor: Sendable {
    var environment = ProcessInfo.processInfo.environment
    var home = FileManager.default.homeDirectoryForCurrentUser
    var run: @Sendable (URL, [String]) async throws -> Int32 = { tool, arguments in
        try await ArchiveProcess.run(tool: tool, arguments: arguments).status
    }
    var exclusiveRename: @Sendable (String, String) -> Int32 = { renamex_np($0, $1, UInt32(RENAME_EXCL)) }

    @concurrent func compress(_ sources: [URL], format: ArchiveCompression) async throws -> URL {
        let files = FileManager.default
        guard !sources.isEmpty, sources.allSatisfy({ $0.isFileURL && files.fileExists(atPath: $0.path) }) else {
            throw ArchiveFailure.filesystem("selection")
        }
        // Without following symlinks: a dangling link still blocks the rename below.
        let exists = { (url: URL) in (try? files.attributesOfItem(atPath: url.path)) != nil }
        let folder = sources[0].deletingLastPathComponent()
        let temporary = folder.appending(path: ".\(UUID()).\(format.suffix)")
        defer { if files.fileExists(atPath: temporary.path) { try? files.removeItem(at: temporary) } }
        let tool: URL
        var inputs = sources
        let staging = folder.appending(path: ".\(UUID())")
        defer { if files.fileExists(atPath: staging.path) { try? files.removeItem(at: staging) } }
        let duplicateLeaves = Set(sources.map { $0.lastPathComponent.lowercased() }).count < sources.count
        if (format == .zip && sources.count > 1) || duplicateLeaves {
            try files.createDirectory(at: staging, withIntermediateDirectories: false)
            inputs = []
            for source in sources {
                try Task.checkCancellation()
                var destination = staging.appending(path: source.lastPathComponent)
                var number = 1
                while exists(destination) {
                    number += 1
                    destination = staging.appending(path: Self.numbered(source, number))
                }
                try files.copyItem(at: source, to: destination)
                inputs.append(destination)
            }
            if format == .zip { inputs = [staging] }
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
        return try JobOutput.publish(temporary, in: folder, stem: format.stem(sources: sources),
                                     suffix: "." + format.suffix, exclusiveRename: exclusiveRename)
    }

    /// `x.tar.gz` → `x (2).tar.gz`, `App.app` → `App (2).app`; a plain folder such as `v1.2` → `v1.2 (2)`.
    static func numbered(_ source: URL, _ number: Int) -> String {
        let name = source.lastPathComponent
        let values = try? source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard values?.isDirectory != true || values?.isPackage == true,
              let dot = name.dropFirst().firstIndex(of: ".") else { return "\(name) (\(number))" }
        return "\(name[..<dot]) (\(number))\(name[dot...])"
    }

    private func locate(_ name: String, install: String) throws -> URL {
        guard let tool = ArchiveToolLocator(environment: environment, home: home, name: name).locate() else {
            throw ArchiveFailure.compressionToolMissing(install)
        }
        return tool
    }
}
