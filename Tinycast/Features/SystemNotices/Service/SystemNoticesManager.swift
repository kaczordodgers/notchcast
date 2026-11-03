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

    init(interval: Duration = tailscaleInterval,
         readTailscale: @escaping ReadTailscale = { await TailscaleStatusService().read() }) {
        self.interval = interval
        self.readTailscale = readTailscale
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let current = generation
        let wifi = NWPathMonitor(requiredInterfaceType: .wifi)
        wifi.pathUpdateHandler = { [weak self] path in
            let available: Bool? = path.status == .requiresConnection ? nil : path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.generation == current, self.isRunning else { return }
                self.consume(.wifi(available))
            }
        }
        wifi.start(queue: DispatchQueue(label: "Notchcast.systemNotices.wifi", qos: .utility))
        self.wifi = wifi
        let routes = NWPathMonitor()
        routes.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current, self.isRunning else { return }
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
        guard isRunning else { return }
        guard reading == nil else { readAgain = true; return }
        let current = generation
        reading = Task { [weak self, readTailscale] in
            let value = await readTailscale()
            guard !Task.isCancelled, let self, self.generation == current, self.isRunning else { return }
            self.reading = nil
            if self.readAgain {
                self.readAgain = false
                self.refreshTailscale()
            } else {
                self.consume(.tailscale(value))
            }
        }
    }

    private func consume(_ reading: SystemNoticeEngine.Reading) {
        guard isRunning else { return }
        for notice in engine.consume(reading) { onNotice?(notice) }
    }

    isolated deinit {
        wifi?.cancel()
        routes?.cancel()
        battery.stop()
        timer?.cancel()
        reading?.cancel()
    }
}
