import AppKit

/// Reads the startup disk at start, when the screens wake and every half hour, and warns once on the island.
@MainActor
final class LowDiskModule: NotchcastModule {
    typealias Reader = @Sendable () async throws -> Int64

    static let noticeID = LowDiskPolicy.statusID
    static let symbol = LowDiskPolicy.symbol

    private let context: NotchcastContext
    private let read: Reader
    private let isDisplayAsleep: @MainActor () -> Bool
    private var policy = LowDiskPolicy()
    private var postedStatus: IslandStatus?
    private var wakeObserver: NotificationCenter.ObservationToken?
    private var timer: Task<Void, Never>?
    private(set) var checking: Task<Void, Never>?
    private(set) var reporting: Task<Void, Never>?
    private var operation = UUID()
    private(set) var isRunning = false

    init(
        context: NotchcastContext, read: @escaping Reader = LowDiskModule.readStartupDisk,
        isDisplayAsleep: @escaping @MainActor () -> Bool = LowDiskModule.isMainDisplayAsleep
    ) {
        self.context = context
        self.read = read
        self.isDisplayAsleep = isDisplayAsleep
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        policy = LowDiskPolicy(hasWarned: context.defaults.bool(forKey: LowDiskPolicy.warnedKey))
        let workspace = NSWorkspace.shared
        wakeObserver = workspace.notificationCenter.addObserver(of: workspace, for: .screensDidWake) { [weak self] _ in
            await self?.check()
        }
        timer = Task { [weak self] in
            while (try? await Task.sleep(for: LowDiskPolicy.checkInterval, tolerance: .seconds(60))) != nil {
                self?.check()
            }
        }
        check()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        timer?.cancel()
        timer = nil
        checking?.cancel()
        checking = nil
        reporting?.cancel()
        reporting = nil
        operation = UUID()
        setStatus(nil)
        context.presenter.end(notice: Self.noticeID)
    }

    /// A new check replaces one in flight, so only the latest reading reaches the policy.
    @discardableResult
    func check() -> Task<Void, Never>? {
        guard isRunning else { return nil }
        checking?.cancel()
        let operation = UUID()
        self.operation = operation
        let read = read
        let task = Task { [weak self] in
            let free = try? await read()
            guard let self, let free, !Task.isCancelled, self.isRunning, self.operation == operation else { return }
            self.checking = nil
            self.apply(free)
        }
        checking = task
        return task
    }

    /// The launcher command: free space on demand, whatever the warning's state.
    @discardableResult
    func showFreeSpace() -> Task<Void, Never>? {
        guard isRunning else { return nil }
        reporting?.cancel()
        let operation = operation
        let read = read
        let task = Task { [weak self] in
            let free = try? await read()
            guard let self, self.isRunning, !Task.isCancelled else { return }
            self.reporting = nil
            if let free, free >= 0, self.policy.hasWarned, self.operation == operation {
                self.checking?.cancel()
                self.checking = nil
                self.apply(free)
            }
            let notice = free.map {
                IslandNotice(id: Self.noticeID, symbol: Self.symbol, text: LowDiskPolicy.available(free: $0))
            } ?? IslandNotice(
                id: Self.noticeID, symbol: Self.symbol,
                text: String(localized: "Couldn’t read disk space", table: "NotchcastLowDisk"), isFailure: true)
            self.context.presenter.post(notice, onTap: nil)
        }
        reporting = task
        return task
    }

    private func apply(_ free: Int64) {
        guard free >= 0, !isDisplayAsleep() else { return }
        let stored = context.defaults.object(forKey: LowDiskPolicy.thresholdKey) as? Int
        let warns = policy.shouldWarn(
            free: free, thresholdGB: LowDiskPolicy.thresholdGB(stored: stored), displayAsleep: false)
        context.defaults.set(policy.hasWarned, forKey: LowDiskPolicy.warnedKey)
        if warns {
            context.presenter.post(
                IslandNotice(id: Self.noticeID, symbol: Self.symbol, text: LowDiskPolicy.warning(free: free),
                             isFailure: true),
                onTap: nil)
        }
        setStatus(policy.status)
    }

    private func setStatus(_ status: IslandStatus?) {
        guard status != postedStatus else { return }
        postedStatus = status
        let tap: @MainActor () -> Void = { [weak self] in self?.showFreeSpace() }
        context.presenter.setStatus(status, for: Self.noticeID, onTap: status == nil ? nil : tap)
    }
}
