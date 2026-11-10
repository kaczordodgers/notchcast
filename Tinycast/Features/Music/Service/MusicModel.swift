import Foundation
import Observation

@MainActor
@Observable
final class MusicModel {
    enum Failure: Equatable, Sendable {
        case unreadable(NowPlaying.Origin)
        case noReplacement
        case launchFailed(String)
        case playbackFailed(String)
    }

    private(set) var nowPlaying: NowPlaying?
    private(set) var failure: Failure?
    private(set) var isEnabled = false
    let lastPlayer: LastPlayer

    @ObservationIgnored private let system = Channel(origin: .system)
    @ObservationIgnored private let soloist = Channel(origin: .soloist)
    @ObservationIgnored private let apps: PlayerApps
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var replacementID = UUID()
    @ObservationIgnored private var commandFailure: Failure?
    @ObservationIgnored var nowPlayingCover: (NowPlaying?) -> NowPlaying? = { $0 }

    init(defaults: UserDefaults, apps: PlayerApps = .workspace(),
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        lastPlayer = LastPlayer(defaults: defaults, canPlay: apps.canPlay)
        self.apps = apps
        self.now = now
        self.sleep = sleep
    }

    isolated deinit {
        stop(system)
        stop(soloist)
        playback?.cancel()
    }

    var canResume: Bool { lastPlayer.isEnabled && lastPlayer.replacement(isInstalled: apps.isInstalled) != nil }

    var position: TimeInterval? { nowPlaying?.position(at: now()) }
    var queue: [MusicQueueItem]? { isEnabled ? soloist.source?.queue : nil }

    func setSystemSource(_ source: (any NowPlayingSource)?) { replace(system, with: source) }

    func reportCommandFailure() {
        guard isEnabled else { return }
        commandFailure = .playbackFailed(nowPlaying?.bundleID ?? "")
        present()
    }
    func setSoloistSource(_ source: (any NowPlayingSource)?) { replace(soloist, with: source) }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            start(system)
            start(soloist)
        } else {
            stop(system)
            stop(soloist)
            playback?.cancel()
            playback = nil
            replacementID = UUID()
            commandFailure = nil
        }
        present()
    }

    func send(_ command: PlayerCommand) {
        guard isEnabled else { return }
        playback?.cancel()
        playback = nil
        replacementID = UUID()
        if nowPlaying == nil, command == .play || command == .togglePlayPause {
            guard lastPlayer.isEnabled else {
                commandFailure = .noReplacement
                present()
                return
            }
            playback = openReplacement(startingPlayback: true, requiresLastPlayer: true)
            return
        }
        let channel = nowPlaying?.origin == .soloist ? soloist : system
        commandFailure = nil
        channel.source?.send(command)
        present()
    }

    func openReplacement(startingPlayback: Bool, requiresLastPlayer: Bool = false) -> Task<Void, Never> {
        let operation = UUID()
        replacementID = operation
        let apps = apps
        let id = lastPlayer.replacement(isInstalled: apps.isInstalled)
        let revision = lastPlayer.revision
        let sleep = sleep
        return Task { [weak self] in
            guard !Task.isCancelled,
                self?.canReplace(operation, id: id, revision: revision, requiresLastPlayer: requiresLastPlayer) == true
            else { return }
            guard let id else {
                self?.finishReplacement(.noReplacement, operation: operation)
                return
            }
            do {
                try await apps.open(id)
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                    self?.canReplace(operation, id: id, revision: revision, requiresLastPlayer: requiresLastPlayer) == true
                else { return }
                self?.finishReplacement(.launchFailed(id), operation: operation)
                return
            }
            guard self?.canReplace(operation, id: id, revision: revision, requiresLastPlayer: requiresLastPlayer) == true
            else { return }
            if startingPlayback {
                do { try await sleep(.seconds(1)) } catch { return }
                guard !Task.isCancelled,
                    self?.canReplace(operation, id: id, revision: revision,
                                     requiresLastPlayer: requiresLastPlayer) == true else { return }
                if let source = self?.source(for: id) {
                    source.send(.play)
                } else {
                    do {
                        for attempt in 0..<3 {
                            do {
                                try await apps.play(id)
                                break
                            } catch where attempt < 2 && PlayerApps.isRetryable(error) {
                                try await sleep(.seconds(1))
                                try Task.checkCancellation()
                                guard self?.canReplace(operation, id: id, revision: revision,
                                                       requiresLastPlayer: requiresLastPlayer) == true else { return }
                            }
                        }
                        try Task.checkCancellation()
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled,
                            self?.canReplace(operation, id: id, revision: revision,
                                             requiresLastPlayer: requiresLastPlayer) == true else { return }
                        self?.finishReplacement(.playbackFailed(id), operation: operation)
                        return
                    }
                }
            }
            guard !Task.isCancelled,
                self?.canReplace(operation, id: id, revision: revision, requiresLastPlayer: requiresLastPlayer) == true
            else { return }
            self?.finishReplacement(nil, operation: operation)
        }
    }

    private func canReplace(_ operation: UUID, id: String?, revision: Int, requiresLastPlayer: Bool) -> Bool {
        replacementID == operation && id == lastPlayer.replacement(isInstalled: apps.isInstalled)
            && (!requiresLastPlayer || (isEnabled && lastPlayer.isEnabled && lastPlayer.revision == revision))
    }

    private func source(for bundleID: String) -> (any NowPlayingSource)? {
        guard let shown = nowPlaying, shown.bundleID == bundleID else { return nil }
        return (shown.origin == .soloist ? soloist : system).source
    }

    private func finishReplacement(_ failure: Failure?, operation: UUID) {
        guard replacementID == operation else { return }
        commandFailure = failure
        present()
    }

    private func replace(_ channel: Channel, with source: (any NowPlayingSource)?) {
        guard channel.source !== source else { return }
        stop(channel)
        channel.source = source
        if isEnabled { start(channel) }
        present()
    }

    private func start(_ channel: Channel) {
        guard let source = channel.source else { return }
        let watchID = channel.watchID
        source.watch { [weak self, weak channel] in
            guard let self, let channel, isEnabled, channel.watchID == watchID, channel.retryWait == nil else { return }
            channel.failedReads = 0
            request(channel)
        }
        request(channel)
    }

    private func stop(_ channel: Channel) {
        channel.watchID = UUID()
        channel.generation += 1
        channel.task?.cancel()
        channel.task = nil
        channel.source?.unwatch()
        channel.track = nil
        channel.failedReads = 0
        channel.retryWait = nil
        channel.failed = false
    }

    private func request(_ channel: Channel) {
        guard isEnabled, let source = channel.source else { return }
        channel.task?.cancel()
        channel.generation += 1
        let generation = channel.generation
        let sleep = sleep
        channel.task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    var track = try await source.read()
                    guard !Task.isCancelled, let self, isEnabled, channel.generation == generation else { return }
                    track?.origin = channel.origin
                    channel.track = track
                    channel.failedReads = 0
                    channel.retryWait = nil
                    channel.failed = false
                    channel.task = nil
                    present()
                    return
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, let self, isEnabled, channel.generation == generation else { return }
                    channel.track = nil
                    channel.failed = true
                    channel.failedReads += 1
                    channel.retryWait = channel.failedReads <= 3 ? .seconds(1 << (channel.failedReads - 1)) : nil
                    present()
                }
                guard let wait = channel.retryWait else {
                    channel.task = nil
                    return
                }
                do { try await sleep(wait) } catch { return }
                guard !Task.isCancelled, channel.generation == generation else { return }
                channel.retryWait = nil
            }
        }
    }

    func present() {
        nowPlaying = nowPlayingCover(MusicSelection.pick(system: system.track, soloist: soloist.track))
        lastPlayer.hear(nowPlaying)
        failure = commandFailure
            ?? (system.failed ? .unreadable(.system) : nil)
            ?? (soloist.failed ? .unreadable(.soloist) : nil)
    }

    @MainActor
    private final class Channel {
        let origin: NowPlaying.Origin
        var source: (any NowPlayingSource)?
        var track: NowPlaying?
        var task: Task<Void, Never>?
        var generation = 0
        var watchID = UUID()
        var failedReads = 0
        var retryWait: Duration?
        var failed = false

        init(origin: NowPlaying.Origin) { self.origin = origin }
    }
}
