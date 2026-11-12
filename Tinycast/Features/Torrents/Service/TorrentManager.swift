import AppKit
import Foundation
import Observation

@Observable @MainActor final class TorrentManager: TorrentQueueHost {
    private struct Request {
        var gid: String?
        var lastPeerActivity: Date
    }

    private(set) var jobs: [TorrentJob] = []
    @ObservationIgnored private let session: any TorrentSession
    @ObservationIgnored private let destination: URL
    @ObservationIgnored private let extraArguments: () -> (arguments: [String], interfaces: [String])
    @ObservationIgnored private let interfacesPresent: ([String]) -> Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let revealFiles: ([URL]) -> Void
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var requests: [UUID: Request] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var sessionStarted = false
    @ObservationIgnored private var sessionInterfaces: [String] = []
    @ObservationIgnored private var stopping = false

    init(
        session: any TorrentSession,
        destination: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
        extraArguments: @escaping () -> (arguments: [String], interfaces: [String]) = { ([], []) },
        interfacesPresent: @escaping ([String]) -> Bool = { _ in true },
        now: (() -> Date)? = nil,
        pollInterval: Duration = .seconds(1),
        revealFiles: @escaping ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    ) {
        self.session = session
        self.destination = destination.standardizedFileURL
        self.extraArguments = extraArguments
        self.interfacesPresent = interfacesPresent
        let origin = SuspendingClock.now
        self.now = now ?? {
            let elapsed = origin.duration(to: SuspendingClock.now).components
            return Date(timeIntervalSince1970: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }
        self.pollInterval = pollInterval
        self.revealFiles = revealFiles
    }

    isolated deinit {
        worker?.cancel()
        session.terminate()
    }

    @discardableResult func enqueue(_ urls: [URL], keepSharing: Bool = false) -> [UUID] {
        guard !stopping else { return [] }
        let ids = urls.map { url in
            let id = UUID()
            jobs.append(TorrentJob(id: id, source: url, destination: destination, keepSharing: keepSharing))
            requests[id] = Request(lastPeerActivity: now())
            return id
        }
        startWorker()
        return ids
    }

    func cancel(_ id: UUID) {
        guard let index = self.index(id), jobs[index].state.isRunning else { return }
        jobs[index].state = .cancelled
        jobs[index].speed = 0
    }

    @discardableResult func tryAgain(_ id: UUID) -> UUID? {
        guard let job = jobs.first(where: { $0.id == id }), [.failed, .cancelled].contains(job.state) else { return nil }
        guard let index = self.index(id) else { return nil }
        let replacement = UUID()
        jobs[index] = TorrentJob(id: replacement, source: job.source, destination: destination, keepSharing: job.keepSharing)
        requests[replacement] = Request(lastPeerActivity: now())
        startWorker()
        return replacement
    }

    func dismiss(_ id: UUID) {
        guard let index = self.index(id), !jobs[index].state.isRunning else { return }
        jobs.remove(at: index)
    }

    func reveal(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        revealFiles(job.files.isEmpty ? [job.destination] : job.files)
    }

    func stop() async {
        guard !stopping else { return }
        stopping = true
        for index in jobs.indices where jobs[index].state.isRunning {
            jobs[index].state = .cancelled
            jobs[index].speed = 0
        }
        let previous = worker
        previous?.cancel()
        await previous?.value
        await session.stop()
        worker = nil
        requests.removeAll()
        sessionStarted = false
        stopping = false
    }

    private func startWorker() {
        guard worker == nil, !requests.isEmpty else { return }
        worker = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.step() else { return }
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    private func step() async -> Duration? {
        do {
            try await removeStopped()
            let ids = jobs.filter { $0.state.isRunning }.map(\.id)
            for id in ids {
                try Task.checkCancellation()
                guard let index = self.index(id), jobs[index].state.isRunning else { continue }
                if requests[id]?.gid == nil { try await submit(id) }
                guard let index = self.index(id), jobs[index].state.isRunning, let gid = requests[id]?.gid else { continue }
                let status: TorrentStatus
                do {
                    status = try await session.status(gid)
                } catch let failure as TorrentFailure {
                    guard case .rpc = failure else { throw failure }
                    if let index = self.index(id), jobs[index].state.isRunning { fail(index, failure) }
                    continue
                }
                let files: [URL]
                do {
                    files = try await Self.outputFiles(status, destination: destination)
                } catch {
                    if let index = self.index(id), jobs[index].state.isRunning {
                        fail(index, (error as? TorrentFailure) ?? .invalidResponse)
                    }
                    continue
                }
                try Task.checkCancellation()
                guard let index = self.index(id), jobs[index].state.isRunning, requests[id]?.gid == gid else { continue }
                if let children = status.followedBy, !children.isEmpty {
                    guard children.count == 1 else { throw TorrentFailure.invalidResponse }
                    requests[id]?.gid = children[0]
                } else {
                    jobs[index].files = files
                    do { try apply(status, to: index) } catch {
                        fail(index, (error as? TorrentFailure) ?? .invalidResponse)
                    }
                }
            }
            try await removeStopped()
        } catch is CancellationError {
            return nil
        } catch {
            if sessionStarted && session.isAlive { return pollInterval }
            let failure = (error as? TorrentFailure) ?? .rpcUnavailable
            for index in jobs.indices where jobs[index].state.isRunning { fail(index, failure) }
            requests.removeAll()
            await session.stop()
            sessionStarted = false
        }
        if requests.isEmpty {
            await session.stop()
            sessionStarted = false
            if !requests.isEmpty { return .zero }
            worker = nil
            return nil
        }
        return pollInterval
    }

    private func submit(_ id: UUID) async throws {
        guard let index = self.index(id) else { return }
        let submission: TorrentSubmission
        do {
            submission = try await TorrentSubmission.read(jobs[index].source)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let index = self.index(id), jobs[index].state.isRunning {
                fail(index, (error as? TorrentFailure) ?? .invalidInput)
            }
            return
        }
        try Task.checkCancellation()
        guard let index = self.index(id), jobs[index].state.isRunning else { return }
        if jobs.contains(where: { $0.id != id && $0.state.isRunning && $0.infoHash == submission.infoHash }) {
            fail(index, .alreadyRunning)
            return
        }
        jobs[index].infoHash = submission.infoHash
        jobs[index].name = submission.name
        if !sessionStarted {
            let network = extraArguments()
            try await session.start(extraArguments: network.arguments)
            try Task.checkCancellation()
            sessionInterfaces = network.interfaces
            sessionStarted = true
        }
        guard let index = self.index(id), jobs[index].state.isRunning else { return }
        jobs[index].usesIPhone = !sessionInterfaces.isEmpty && interfacesPresent(sessionInterfaces)
        let gid: String
        do {
            gid = try await session.add(submission, destination: destination, keepSharing: jobs[index].keepSharing)
        } catch let failure as TorrentFailure {
            guard case .rpc = failure else { throw failure }
            if let index = self.index(id), jobs[index].state.isRunning { fail(index, failure) }
            return
        }
        requests[id]?.gid = gid
        requests[id]?.lastPeerActivity = now()
        try Task.checkCancellation()
    }

    private func apply(_ status: TorrentStatus, to index: Int) throws {
        let id = jobs[index].id
        if let hash = status.infoHash, !hash.isEmpty, hash.lowercased() != jobs[index].infoHash {
            throw TorrentFailure.invalidResponse
        }
        let previousBytes = jobs[index].bytesDone
        jobs[index].bytesDone = status.bytesDone
        jobs[index].bytesTotal = status.bytesTotal
        jobs[index].speed = status.speed
        jobs[index].peers = status.peers
        jobs[index].seeders = status.seeders
        if let name = status.bittorrent?.info?.name, !name.isEmpty { jobs[index].name = name }
        switch status.status {
        case "complete":
            jobs[index].state = .finished
            jobs[index].speed = 0
        case "error":
            fail(index, .download(code: status.errorCode ?? "", message: status.errorMessage ?? ""))
        case "removed":
            jobs[index].state = .cancelled
            jobs[index].speed = 0
        case "active", "waiting", "paused":
            if status.seeder == "true" {
                jobs[index].state = .sharing
            } else {
                jobs[index].state = jobs[index].name == nil ? .findingPeers : .downloading
            }
            if status.peers > 0 || status.bytesDone > previousBytes || status.status != "active"
                || jobs[index].state == .sharing {
                requests[id]?.lastPeerActivity = now()
            } else if let lastActivity = requests[id]?.lastPeerActivity, now().timeIntervalSince(lastActivity) >= 600 {
                fail(index, .noPeers)
            }
        default:
            throw TorrentFailure.invalidResponse
        }
    }

    private func removeStopped() async throws {
        for id in Array(requests.keys) {
            if let index = self.index(id), jobs[index].state.isRunning { continue }
            if let gid = requests[id]?.gid {
                do { try await session.remove(gid) } catch let failure as TorrentFailure {
                    guard case .rpc(1, _) = failure else { throw failure }
                }
            }
            try Task.checkCancellation()
            requests.removeValue(forKey: id)
        }
    }

    private func fail(_ index: Int, _ failure: TorrentFailure) {
        jobs[index].state = .failed
        jobs[index].error = failure
        jobs[index].speed = 0
    }

    private func index(_ id: UUID) -> Int? { jobs.firstIndex { $0.id == id } }

    @concurrent private static func outputFiles(_ status: TorrentStatus, destination: URL) async throws -> [URL] {
        let files = (status.files ?? []).map { URL(fileURLWithPath: $0.path).standardizedFileURL }
            .filter { $0.path.hasPrefix(destination.path + "/") }
        if status.status == "complete" || status.seeder == "true" {
            for file in files {
                guard WebRules.stampQuarantine(file.path, onlyIfMissing: true) == 0 else {
                    throw TorrentFailure.download(code: "quarantine", message: "Quarantine failed")
                }
            }
        }
        return files
    }
}
