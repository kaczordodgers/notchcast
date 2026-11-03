import AppKit
import Foundation
import Network

@MainActor
final class SystemNoticesManager {
    typealias ReadTailscale = @Sendable () async -> TailscaleState
    static let tailscaleInterval: Duration = .seconds(300)
    var onNotice: ((SystemNoticeEngine.Notice) -> Void)?
    private(set) var isRunning = false
    private var engine = SystemNoticeEngine()
    private let readTailscale: ReadTailscale
    private let interval: Duration
    private let battery = MacBatteryMonitor()
    private var wifi: NWPathMonitor?
    private var routes: NWPathMonitor?
    private var timer: Task<Void, Never>?
    private var reading: Task<Void, Never>?
    private var readAgain = false
    private var generation = UUID()
    private var sleeping = false
    private var locked = false
    private let observeSystem: Bool
    private var workspaceTokens: [NotificationCenter.ObservationToken] = []
    private var lockTasks: [Task<Void, Never>] = []

    private var canMonitor: Bool { isRunning && !sleeping && !locked }

    init(interval: Duration = tailscaleInterval, observeSystem: Bool = true,
         readTailscale: @escaping ReadTailscale = { await TailscaleStatusService().read() }) {
        self.interval = interval
        self.observeSystem = observeSystem
        self.readTailscale = readTailscale
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        guard observeSystem else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(of: NSWorkspace.self, for: .willSleep) { [weak self] _ in
                self?.setSleeping(true)
            },
            center.addObserver(of: NSWorkspace.self, for: .didWake) { [weak self] _ in
                self?.setSleeping(false)
            },
        ]
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let notifications = DistributedNotificationCenter.default().notifications(named: .init(name))
            lockTasks.append(Task { [weak self] in
                for await _ in notifications {
                    guard !Task.isCancelled else { return }
                    self?.setLocked(locked)
                }
            })
        }
        startSources()
    }

    func setSleeping(_ value: Bool) {
        sleeping = value
        resetSources()
    }

    func setLocked(_ value: Bool) {
        locked = value
        resetSources()
    }

    private func resetSources() {
        stopSources()
        if canMonitor, observeSystem { startSources() }
    }

    private func startSources() {
        let current = generation
        let wifi = NWPathMonitor(requiredInterfaceType: .wifi)
        wifi.pathUpdateHandler = { [weak self] path in
            let available: Bool? = path.status == .requiresConnection ? nil : path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.generation == current, self.canMonitor else { return }
                self.consume(.wifi(available))
            }
        }
        wifi.start(queue: DispatchQueue(label: "Notchcast.systemNotices.wifi", qos: .utility))
        self.wifi = wifi
        let routes = NWPathMonitor()
        routes.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current, self.canMonitor else { return }
                self.refreshTailscale()
            }
        }
        routes.start(queue: DispatchQueue(label: "Notchcast.systemNotices.routes", qos: .utility))
        self.routes = routes
        battery.start { [weak self] value in self?.consume(.battery(value)) }
        timer = Task { [weak self, interval] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval, tolerance: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.refreshTailscale()
            }
        }
        refreshTailscale()
    }

    func stop() {
        isRunning = false
        stopSources()
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens { center.removeObserver(token) }
        workspaceTokens = []
        for task in lockTasks { task.cancel() }
        lockTasks = []
        sleeping = false
        locked = false
    }

    private func stopSources() {
        generation = UUID()
        wifi?.cancel()
        wifi = nil
        routes?.cancel()
        routes = nil
        battery.stop()
        timer?.cancel()
        timer = nil
        reading?.cancel()
        reading = nil
        readAgain = false
        engine = SystemNoticeEngine()
    }

    func refreshTailscale() {
        guard canMonitor else { return }
        guard reading == nil else { readAgain = true; return }
        let current = generation
        reading = Task { [weak self, readTailscale] in
            let value = await readTailscale()
            guard !Task.isCancelled, let self, self.generation == current, self.canMonitor else { return }
            self.reading = nil
            if self.readAgain {
                self.readAgain = false
                self.refreshTailscale()
            } else {
                self.consume(.tailscale(value))
            }
        }
    }

    func consume(_ reading: SystemNoticeEngine.Reading) {
        guard canMonitor else { return }
        for notice in engine.consume(reading) { onNotice?(notice) }
    }

    isolated deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens { center.removeObserver(token) }
        for task in lockTasks { task.cancel() }
        wifi?.cancel()
        routes?.cancel()
        battery.stop()
        timer?.cancel()
        reading?.cancel()
    }
}
