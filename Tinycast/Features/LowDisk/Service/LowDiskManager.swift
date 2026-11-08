import AppKit
import Foundation
import Observation
import OSLog

@MainActor @Observable
final class LowDiskManager {
    typealias Read = @Sendable () async throws -> LowDiskEngine.Space
    static let checkInterval: Duration = .seconds(600)
    private static let spellKey = "notchcast.lowDisk.isLow"
    private static let log = Logger(subsystem: NotchcastIdentity.current.loggerSubsystem(fallback: NotchcastIdentity.displayName), category: "LowDisk")

    private(set) var engine: LowDiskEngine
    private(set) var isRunning = false
    var onNotice: ((LowDiskEngine.Space) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let read: Read
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let wakeCenter: NotificationCenter
    @ObservationIgnored private var wakeToken: NotificationCenter.ObservationToken?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var readAgain = false

    init(defaults: UserDefaults = NotchcastIdentity.current.defaults,
         volumeURL: URL = URL(filePath: NSHomeDirectory()),
         interval: Duration = checkInterval,
         wakeCenter: NotificationCenter = NSWorkspace.shared.notificationCenter, read: Read? = nil) {
        self.defaults = defaults
        self.read = read ?? { try await Self.readSpace(at: volumeURL) }
        self.interval = interval
        self.wakeCenter = wakeCenter
        engine = LowDiskEngine(isLow: defaults.bool(forKey: Self.spellKey))
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        wakeToken = wakeCenter.addObserver(of: NSWorkspace.self, for: .didWake) { [weak self] _ in
            self?.refresh()
        }
        timer = Task { [weak self, interval] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval, tolerance: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
        refresh()
    }

    func stop() {
        isRunning = false
        generation = UUID()
        timer?.cancel()
        timer = nil
        reading?.cancel()
        reading = nil
        readAgain = false
        if let wakeToken { wakeCenter.removeObserver(wakeToken) }
        wakeToken = nil
    }

    func refresh() {
        guard isRunning else { return }
        guard reading == nil else { readAgain = true; return }
        let current = generation
        reading = Task { [weak self, read] in
            do {
                let space = try await read()
                guard !Task.isCancelled, let self, self.generation == current, self.isRunning else { return }
                let notice = self.engine.consume(space)
                self.defaults.set(self.engine.isLow, forKey: Self.spellKey)
                if notice { self.onNotice?(space) }
            } catch {
                if !Task.isCancelled { Self.log.error("Disk capacity read failed: \(error.localizedDescription)") }
            }
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.reading = nil
            if self.readAgain {
                self.readAgain = false
                self.refresh()
            }
        }
    }

    func settled() async {
        while let reading { await reading.value }
    }

    @concurrent
    private static func readSpace(at url: URL) async throws -> LowDiskEngine.Space {
        let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ])
        guard let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { throw CocoaError(.fileReadUnknown) }
        let space = LowDiskEngine.Space(free: free, total: Int64(total))
        guard space.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return space
    }

    isolated deinit {
        timer?.cancel()
        reading?.cancel()
        if let wakeToken { wakeCenter.removeObserver(wakeToken) }
    }
}
