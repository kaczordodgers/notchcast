import CryptoKit
import Foundation
import OSLog

@MainActor
protocol SoloistBuildSource: AnyObject {
    func installed(excluding: Set<URL>) async throws -> SoloistBuild?
    func install() async throws -> SoloistBuild
}

@MainActor
final class SoloistInstaller: SoloistBuildSource {
    typealias Fetch = @Sendable (URL) async throws -> Data
    typealias Probe = @Sendable (URL) async throws -> SoloistBuild?
    nonisolated static let address = URL(string: "https://soloist-builds.spotifycdn.com/soloist_release_osx_arm64.tar.gz")!

    private let files: SoloistFiles
    private let now: @Sendable () -> Date
    private let fetch: Fetch
    private let probe: Probe

    init(files: SoloistFiles = SoloistFiles(), now: @escaping @Sendable () -> Date = Date.init,
         fetch: @escaping Fetch = SoloistInstaller.download, probe: @escaping Probe = SoloistInstaller.version) {
        self.files = files
        self.now = now
        self.fetch = fetch
        self.probe = probe
    }

    func installed(excluding: Set<URL> = []) async throws -> SoloistBuild? {
        try await Self.scan(files: files, excluding: excluding, now: now(), probe: probe)
    }

    /// Only the Download button installs, so every press tries again; a failure names its step.
    func install() async throws -> SoloistBuild {
        try Task.checkCancellation()
        do {
            let build = try await Self.unpack(files: files, fetch: fetch, now: now, probe: probe)
            try Task.checkCancellation()
            return build
        } catch {
            try Task.checkCancellation()
            let failure = (error as? SoloistFailure) ?? .filesystem.detail(SoloistFailure.describe(error))
            Logger(subsystem: NotchcastIdentity.current.bundleID, category: "Soloist")
                .error("Soloist download: \(String(describing: failure), privacy: .public)")
            throw failure
        }
    }

    @concurrent
    private static func scan(files: SoloistFiles, excluding: Set<URL>, now: Date,
                             probe: Probe) async throws -> SoloistBuild? {
        guard FileManager.default.fileExists(atPath: files.builds.path) else { return nil }
        let folders = try FileManager.default.contentsOfDirectory(at: files.builds, includingPropertiesForKeys: nil)
        var best: SoloistBuild?
        for folder in folders {
            try Task.checkCancellation()
            let executable = folder.appending(path: "soloist").standardizedFileURL
            let digest = folder.lastPathComponent
            guard !excluding.contains(executable), digest.count == 64, digest.allSatisfy(\.isHexDigit),
                  files.ownsExecutable(executable.path),
                  FileManager.default.isExecutableFile(atPath: executable.path),
                  let data = try? Data(contentsOf: executable), data.count <= SoloistArchiveRules.maxUnpacked,
                  sha256(data) == digest else { continue }
            let candidate = try await probe(executable)
            try Task.checkCancellation()
            guard let build = candidate, SoloistBuild.isUsable(built: build.built, now: now) else { continue }
            if best.map({ build.built > $0.built }) ?? true { best = build }
        }
        return best
    }

    @concurrent
    private static func unpack(files: SoloistFiles, fetch: Fetch, now: @Sendable () -> Date,
                               probe: Probe) async throws -> SoloistBuild {
        try files.makeFolders()
        let staging = files.root.appending(path: "staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let data = try await fetch(address)
        try Task.checkCancellation()
        guard data.count <= SoloistArchiveRules.maxPacked else { throw SoloistFailure.archive.detail("\(data.count) bytes") }
        return try await extract(data, staging: staging, files: files, now: now, probe: probe)
    }

    @concurrent
    private static func extract(_ data: Data, staging: URL, files: SoloistFiles,
                                now: @Sendable () -> Date, probe: Probe) async throws -> SoloistBuild {
        let archive = staging.appending(path: "soloist.tar.gz")
        try data.write(to: archive)
        let listing = try await tar(["-tvzf", archive.path])
        let names = try SoloistArchiveRules.check(SoloistArchiveRules.entries(listing))
        let unpacked = staging.appending(path: "unpacked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: false)
        _ = try await tar(["-xzf", archive.path, "-C", unpacked.path, "--"] + names)
        let staged = unpacked.appending(path: "soloist")
        let values = try staged.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= SoloistArchiveRules.maxUnpacked else {
            throw SoloistFailure.archive.detail("soloist: not a regular file under the size limit")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        guard let build = try await probe(staged) else {
            throw SoloistFailure.refusedBuild.detail("soloist --version: no version")
        }
        guard SoloistBuild.isUsable(built: build.built, now: now()) else {
            throw SoloistFailure.refusedBuild.detail("soloist \(build.version): built \(build.built.ISO8601Format())")
        }
        try Task.checkCancellation()
        let digest = sha256(try Data(contentsOf: staged))
        let folder = files.builds.appending(path: digest, directoryHint: .isDirectory)
        let executable = folder.appending(path: "soloist").standardizedFileURL
        let intact = {
            files.ownsExecutable(executable.path) && (try? Data(contentsOf: executable)).map { sha256($0) == digest } == true
        }
        if FileManager.default.fileExists(atPath: folder.path), !intact() {
            try FileManager.default.moveItem(at: folder, to: staging.appending(path: "rejected-build"))
        }
        if !FileManager.default.fileExists(atPath: folder.path) {
            do { try FileManager.default.moveItem(at: unpacked, to: folder) } catch { guard intact() else { throw error } }
        }
        return SoloistBuild(executable: executable, version: build.version, built: build.built)
    }

    @concurrent
    private static func version(of executable: URL) async throws -> SoloistBuild? {
        do {
            let output = try await SoloistProcess.run(executable, arguments: ["--version"])
            guard output.status == 0, let parsed = SoloistBuild.parseVersion(output.text) else { return nil }
            return SoloistBuild(executable: executable, version: parsed.version, built: parsed.built)
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @concurrent
    private static func tar(_ arguments: [String]) async throws -> String {
        let output: SoloistProcess.Output
        do {
            output = try await SoloistProcess.run(URL(filePath: "/usr/bin/tar"), arguments: arguments)
        } catch let failure as SoloistFailure {
            throw SoloistFailure.unpack.detail(SoloistFailure.describe(failure))
        }
        guard output.status == 0 else {
            let said = output.text.split(separator: "\n").prefix(2).joined(separator: " ").prefix(300)
            throw SoloistFailure.unpack.detail("tar \(arguments[0]) exited \(output.status): \(said)")
        }
        return output.text
    }

    @concurrent
    private static func download(_ url: URL) async throws -> Data {
        let config = NotchcastIdentity.sessionConfiguration()
        let delegate = DownloadDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: URLRequest(url: url, timeoutInterval: 60))
            guard let http = response as? HTTPURLResponse else { throw SoloistFailure.download.detail("not an HTTP response") }
            guard http.statusCode == 200 else { throw SoloistFailure.httpStatus(http.statusCode) }
            guard response.url == url else {
                throw SoloistFailure.download.detail("answered from \(response.url?.absoluteString ?? "no address")")
            }
            guard response.expectedContentLength <= SoloistArchiveRules.maxPacked else {
                throw SoloistFailure.archive.detail("\(response.expectedContentLength) bytes")
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < SoloistArchiveRules.maxPacked else {
                    throw SoloistFailure.archive.detail("over \(data.count) bytes")
                }
                data.append(byte)
            }
            return data
        } catch let error where !(error is SoloistFailure || error is CancellationError) {
            throw SoloistFailure.download.detail(SoloistFailure.describe(error))
        }
    }

    nonisolated static func readDownload(_ file: URL) throws -> Data {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, size <= SoloistArchiveRules.maxPacked else { throw SoloistFailure.archive }
        let data = try Data(contentsOf: file)
        guard data.count <= SoloistArchiveRules.maxPacked else { throw SoloistFailure.archive }
        return data
    }

    private final class DownloadDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
