import Foundation
import Observation

@MainActor
@Observable
final class SoloistSpeaker {
    private(set) var state: SoloistSpeakerState = .off
    private(set) var port: Int?
    private(set) var build: SoloistBuild?
    private(set) var installFailure: SoloistFailure?
    @ObservationIgnored var onPort: ((Int?) -> Void)?

    @ObservationIgnored private let key: SoloistKey
    @ObservationIgnored private let files: SoloistFiles
    @ObservationIgnored private let builds: any SoloistBuildSource
    @ObservationIgnored private let launcher: any SoloistLauncher
    @ObservationIgnored private let processes: any SoloistProcessList
    @ObservationIgnored private let schedule: SoloistSchedule
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let probe: @MainActor (Int) async -> Bool
    @ObservationIgnored private let watch: @MainActor (@escaping @MainActor () -> Void,
                                            @escaping @MainActor () -> Void,
                                            @escaping @MainActor () -> Void) -> SoloistCancellation
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var child: (any SoloistChild)?
    @ObservationIgnored private var childRun: UUID?
    @ObservationIgnored private var retiring: [UUID: any SoloistChild] = [:]
    @ObservationIgnored private var restartWhenStopped = false
    @ObservationIgnored private var startedAt: TimeInterval?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var expiryFailures = 0
    @ObservationIgnored private var rejectedBuilds: Set<URL> = []
    @ObservationIgnored private var pending: SoloistCancellation?
    @ObservationIgnored private var expiryCheck: SoloistCancellation?
    @ObservationIgnored private var peerWatches: [SoloistCancellation] = []
    @ObservationIgnored private var launchChecks: [SoloistCancellation] = []
    @ObservationIgnored private var events: SoloistCancellation?
    @ObservationIgnored private(set) var preparing: Task<Void, Never>?
    @ObservationIgnored private(set) var installing: Task<Void, Never>?
    @ObservationIgnored private(set) var checking: Task<Void, Never>?

    init(key: SoloistKey, files: SoloistFiles = SoloistFiles(), builds: any SoloistBuildSource,
         launcher: any SoloistLauncher, processes: any SoloistProcessList,
         deviceName: String = "Notchcast", schedule: SoloistSchedule = .live,
         now: @escaping () -> Date = Date.init,
         probe: @escaping @MainActor (Int) async -> Bool = SoloistSystemEvents.answers,
         watch: @escaping @MainActor (@escaping @MainActor () -> Void,
                           @escaping @MainActor () -> Void,
                           @escaping @MainActor () -> Void) -> SoloistCancellation = SoloistSystemEvents.watch) {
        self.key = key
        self.files = files
        self.builds = builds
        self.launcher = launcher
        self.processes = processes
        self.deviceName = deviceName
        self.schedule = schedule
        self.now = now
        self.probe = probe
        self.watch = watch
        key.onChange = { [weak self] in self?.keyChanged() }
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            self.enabled = false
            cancelWork()
            events = nil
            restartWhenStopped = false
            stopChild()
            state = .off
            return
        }
        guard !self.enabled else { return }
        self.enabled = true
        failures = 0
        expiryFailures = 0
        events = watch({ [weak self] in self?.recheckAfterWake() }, { [weak self] in self?.appLaunched() },
                       { [weak self] in self?.terminate() })
        begin()
    }

    func installBuild() {
        guard installing == nil else { return }
        cancelWork()
        installFailure = nil
        state = .downloading
        let token = generation
        let builds = builds
        installing = Task { [weak self] in
            do {
                let build = try await builds.install()
                guard !Task.isCancelled, let self, token == self.generation else { return }
                self.installing = nil
                self.rejectedBuilds.remove(build.executable)
                self.build = build
                if self.enabled {
                    self.stopChild()
                    self.begin()
                } else { self.state = .off }
            } catch {
                guard !Task.isCancelled, let self, token == self.generation else { return }
                self.installing = nil
                self.installFailure = (error as? SoloistFailure) ?? .download
                if self.child != nil {
                    self.state = .starting
                    self.checkPort(until: self.schedule.now() + 10)
                } else if self.enabled { self.begin() } else { self.state = .off }
            }
        }
    }

    func refreshInstalledBuild() async {
        let token = generation
        do {
            let installed = try await builds.installed(excluding: rejectedBuilds)
            guard !Task.isCancelled, token == generation, installing == nil else { return }
            build = installed
        } catch { installFailure = (error as? SoloistFailure) ?? .filesystem }
    }

    func recheckAfterWake() {
        guard enabled else { return }
        lookForOthers()
        guard let run = childRun, let port else {
            if child == nil, pending == nil, preparing == nil, installing == nil, !hasFailed { begin() }
            return
        }
        if let build, !SoloistBuild.isUsable(built: build.built, now: now()) {
            expired()
            return
        }
        checking?.cancel()
        let probe = probe
        checking = Task { [weak self] in
            let answers = await probe(port)
            guard !Task.isCancelled, let self, self.enabled, self.childRun == run else { return }
            self.checking = nil
            if answers { self.ready() } else {
                self.stopChild()
                self.begin()
            }
        }
    }

    private var hasFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func keyChanged() {
        guard enabled else { return }
        cancelWork()
        stopChild()
        failures = 0
        begin()
    }

    private func begin() {
        guard enabled, child == nil, installing == nil else { return }
        pending = nil
        peerWatches = []
        do {
            guard try key.value() != nil else { state = .noKey; return }
        } catch { state = .failed(reason: .keyUnavailable); return }
        guard retiring.isEmpty else { restartWhenStopped = true; state = .starting; return }
        guard !waitForPeers() else { return }
        preparing?.cancel()
        generation += 1
        let token = generation
        let builds = builds
        let excluded = rejectedBuilds
        state = .starting
        preparing = Task { [weak self] in
            do {
                let build = try await builds.installed(excluding: excluded)
                guard !Task.isCancelled, let self, self.enabled, token == self.generation else { return }
                self.preparing = nil
                guard let build, SoloistBuild.isUsable(built: build.built, now: self.now()) else {
                    self.state = .needsBuild
                    return
                }
                self.build = build
                guard !self.waitForPeers() else { return }
                self.launch(build)
            } catch {
                guard !Task.isCancelled, let self, self.enabled, token == self.generation else { return }
                self.preparing = nil
                self.state = .failed(reason: (error as? SoloistFailure) ?? .filesystem)
            }
        }
    }

    private func launch(_ build: SoloistBuild) {
        let run = UUID()
        do {
            guard let secret = try key.value() else { state = .noKey; return }
            try files.makeFolders()
            try files.clearPort()
            let arguments = files.arguments(key: secret, deviceName: deviceName)
            let launched = try launcher.launch(build.executable, arguments: arguments) { [weak self] status in
                self?.exited(run: run, status: status)
            }
            child = launched
            childRun = run
        } catch {
            stopChild()
            failedStart(reason: (error as? SoloistFailure) ?? .process)
            return
        }
        startedAt = schedule.now()
        checkPort(until: schedule.now() + 10)
    }

    private func checkPort(until deadline: TimeInterval) {
        guard enabled, child != nil, installing == nil else { return }
        if let port = files.readPort() {
            self.port = port
            ready()
            onPort?(port)
        } else if schedule.now() >= deadline {
            stopChild()
            failedStart(reason: .portTimeout)
        } else {
            pending = schedule.after(0.25) { [weak self] in self?.checkPort(until: deadline) }
        }
    }

    private func ready() {
        guard enabled, child != nil, let port, let build else { return }
        let days = build.daysRemaining(at: now())
        state = days <= 7 ? .expiresSoon(days: days) : .running(port: port)
        expiryCheck = schedule.after(min(86_400, max(0, build.expires.timeIntervalSince(now())))) { [weak self] in
            guard let self, self.enabled else { return }
            if self.now() >= build.expires { self.expired() } else { self.ready() }
        }
    }

    private func exited(run: UUID, status: Int32) {
        if retiring.removeValue(forKey: run) != nil {
            if retiring.isEmpty, restartWhenStopped {
                restartWhenStopped = false
                begin()
            }
            return
        }
        guard childRun == run, child != nil else { return }
        self.child = nil
        childRun = nil
        pending = nil
        expiryCheck = nil
        checking?.cancel()
        checking = nil
        clearPort()
        guard enabled else { return }
        guard installing == nil else {
            if status == 10, let build { rejectedBuilds.insert(build.executable) }
            return
        }
        if let startedAt, schedule.now() - startedAt >= 600 {
            failures = 0
            expiryFailures = 0
        }
        if status == 10 { expired() } else if installing == nil { failedStart(reason: .process) }
    }

    private func expired() {
        if let build { rejectedBuilds.insert(build.executable) }
        cancelWork()
        stopChild()
        state = .needsBuild
        let delay = expiryFailures == 0 ? 0 : min(86_400, 3_600 * pow(2, Double(min(expiryFailures - 1, 5))))
        expiryFailures += 1
        pending = schedule.after(delay) { [weak self] in self?.begin() }
    }

    private func failedStart(reason: SoloistFailure) {
        failures += 1
        guard failures < 5 else { state = .failed(reason: reason); return }
        state = .starting
        pending = schedule.after(min(300, pow(2, Double(failures - 1)))) { [weak self] in self?.begin() }
    }

    private func waitForPeers() -> Bool {
        let peers = processes.soloists().filter { $0.pid != child?.pid }
        guard !peers.isEmpty else { return false }
        state = .waitingForOther
        for peer in peers where files.ownsExecutable(peer.path) {
            processes.stop(peer)
        }
        peerWatches = peers.map { peer in
            processes.watchExit(of: peer.pid) { [weak self] in
                guard let self, self.enabled, self.child == nil, !self.hasFailed else { return }
                self.pending = self.schedule.after(1) { [weak self] in self?.begin() }
            }
        }
        return true
    }

    func lookForOthers() {
        guard enabled, child != nil || preparing != nil else { return }
        let peers = processes.soloists().filter { $0.pid != child?.pid }
        guard !peers.isEmpty else { return }
        cancelWork()
        stopChild()
        _ = waitForPeers()
    }

    private func appLaunched() {
        guard enabled else { return }
        launchChecks = [1.0, 3, 10, 30].map { delay in
            schedule.after(delay) { [weak self] in self?.lookForOthers() }
        }
    }

    private func stopChild() {
        guard let child, let run = childRun else { return }
        self.child = nil
        childRun = nil
        retiring[run] = child
        expiryCheck = nil
        checking?.cancel()
        checking = nil
        pending = nil
        clearPort()
        child.stop()
    }

    private func terminate() {
        setEnabled(false)
    }

    private func clearPort() {
        guard port != nil else { return }
        port = nil
        onPort?(nil)
    }

    private func cancelWork() {
        generation += 1
        preparing?.cancel()
        preparing = nil
        installing?.cancel()
        installing = nil
        checking?.cancel()
        checking = nil
        pending = nil
        expiryCheck = nil
        peerWatches = []
        launchChecks = []
    }

    isolated deinit {
        preparing?.cancel()
        installing?.cancel()
        checking?.cancel()
        child?.stop()
        retiring.values.forEach { $0.stop() }
    }
}
