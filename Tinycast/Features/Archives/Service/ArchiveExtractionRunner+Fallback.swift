import Darwin
import Foundation

extension ArchiveExtractionRunner {
    func extractFallback(
        _ archive: URL, mode: ArchiveJob.Mode, recovery: ArchiveJob.Recovery?,
        progress: @escaping @MainActor @Sendable (Progress) -> Void
    ) async throws -> URL? {
        var route = ArchiveEngineRoute.route(archive)
        var zipEncoding: String?
        if mode == .inPlace, recovery?.readyToPublish == true { return nil }
        let journal = URL(fileURLWithPath: archive.path + ".hatchzip")
        if archive.pathExtension.lowercased() == "zip", !ArchiveFiles.exists(journal),
           let attributes = try? ArchiveFiles.attributes(archive), attributes.st_mode & S_IFMT == S_IFREG {
            let inspection = ArchiveZIPEncoding.inspect(try Data(contentsOf: archive, options: .alwaysMapped))
            route = ArchiveEngineRoute.route(archive, windowsZIP: inspection.requiresUnar)
            zipEncoding = inspection.encoding
        }
        guard let route, route != .hatchzip else { return nil }
        if let output = try ArchiveRecovery.recover(in: archive.deletingLastPathComponent(), archive: archive) {
            return output
        }
        let attributes = try ArchiveFiles.fresh(archive)
        let tool = try route == .xad ? fallbackTools.require("unar")
            : route == .zstd ? fallbackTools.require("zstd") : URL(fileURLWithPath: "/usr/bin/bsdtar")
        let lister = try route == .xad ? fallbackTools.require("lsar") : tool
        let (staging, warning) = try ArchiveFiles.stage(beside: archive)
        var durable = ArchiveRecovery(archive: archive, staging: staging, inPlace: false, state: .running)
        do {
            try durable.save()
            let maximum = ArchiveFallbackLimits.maximumBytes(archiveBytes: attributes.st_size)
            let intermediate = staging.appending(path: ".notchcast-input-\(UUID().uuidString).tar")
            var source = archive
            if route == .zstd, !ArchiveEngineRoute.isSingleStream(archive) {
                _ = try await fallbackCommand(tool, ["-d", "-c", "--", archive.path], output: intermediate, maximum: maximum)
                source = intermediate
            }
            let listing: ArchiveListing
            var encoding: String?
            if route == .xad {
                let flags = zipEncoding.map { ["-e", $0] } ?? []
                let result = try await fallbackCommand(lister, ["-j", "-nr"] + flags + [archive.path], capture: true)
                let parsed = try ArchiveFallbackListing.lsar(result.output)
                listing = parsed.listing
                encoding = parsed.encoding
            } else if ArchiveEngineRoute.isSingleStream(archive) {
                let bytes: Int64
                if route == .zstd {
                    bytes = try await fallbackCommand(tool, ["-d", "-c", "--", archive.path], maximum: maximum).outputBytes
                } else {
                    bytes = try await fallbackCommand(URL(fileURLWithPath: "/usr/bin/gzip"),
                        ["-d", "-c", "--", archive.path], maximum: maximum).outputBytes
                }
                listing = ArchiveFallbackListing.stream(archive, bytes: bytes)
            } else {
                let result = try await fallbackCommand(URL(fileURLWithPath: "/usr/bin/bsdtar"),
                                                       ["-tvf", source.path, "--numeric-owner"], capture: true)
                listing = try ArchiveFallbackListing.bsdtar(result.output)
            }
            let reserved: [ArchiveListing.Entry] = source == intermediate
                ? [.init(path: intermediate.lastPathComponent, isDirectory: false, isSymlink: false)] : []
            try ArchiveRules.validate(ArchiveListing(entries: listing.entries + reserved, totalBytes: listing.totalBytes),
                                      archiveBytes: attributes.st_size)
            guard let total = listing.totalBytes else { throw ArchiveFailure.invalidListing }
            try ArchiveFallbackSpace.check(staging, additionalBytes: total)
            try Task.checkCancellation()
            let update = Progress(recovery: .init(staging: staging, totalBytes: total, quarantine: warning),
                                  mode: .keepArchive, fallback: mode == .inPlace ? .inPlaceCheckRefused(1) : nil)
            await progress(update)
            let report: @Sendable () async -> Void = {
                await Self.reportBytes(update, limit: total, progress: progress)
            }
            if route == .xad {
                let flags = encoding.map { ["-e", $0] } ?? []
                _ = try await fallbackCommand(tool, ["-q", "-nr", "-D", "-f", "-k", "fork", "-o", staging.path]
                    + flags + [archive.path], progress: report)
            } else if ArchiveEngineRoute.isSingleStream(archive) {
                let output = staging.appending(path: archive.deletingPathExtension().lastPathComponent)
                if route == .zstd {
                    _ = try await fallbackCommand(tool, ["-d", "-c", "--", archive.path],
                                                  output: output, maximum: total, progress: report)
                } else {
                    _ = try await fallbackCommand(URL(fileURLWithPath: "/usr/bin/gzip"),
                        ["-d", "-c", "--", archive.path], output: output, maximum: total, progress: report)
                }
            } else {
                _ = try await fallbackCommand(URL(fileURLWithPath: "/usr/bin/bsdtar"),
                    ["-xf", source.path, "-C", staging.path, "--no-same-owner", "--no-same-permissions"], progress: report)
            }
            if source == intermediate { try FileManager.default.removeItem(at: intermediate) }
            durable.state = .finishedExtract
            try durable.save()
            try Task.checkCancellation()
            return try finish(update.recovery, archive: archive)
        } catch {
            try Self.cleanupFailure(durable, route: route)
            throw error
        }
    }

    private func fallbackCommand(
        _ tool: URL, _ arguments: [String], capture: Bool = false,
        output: URL? = nil, maximum: Int64? = nil,
        progress: @escaping @Sendable () async -> Void = {}
    ) async throws -> ArchiveProcess.Result {
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        let result = try await ArchiveProcess.run(tool: tool, arguments: arguments, captureOutput: capture,
                                                outputFile: output, maximumOutputBytes: maximum,
                                                environment: environment, progress: progress)
        if tool.lastPathComponent == "lsar", result.status == 2 { throw ArchiveFailure.passwordRequired }
        guard result.status == 0 else { throw ArchiveFailure.fallbackToolFailed(tool.lastPathComponent, result.status) }
        return result
    }
}
