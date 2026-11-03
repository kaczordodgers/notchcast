import AppKit
import Observation
import os

@MainActor @Observable
final class LiveTimerStore {
    private(set) var timers: [LiveTimerEntry] = [] {
        didSet {
            guard timers != oldValue else { return }
            do {
                defaults.set(try JSONEncoder().encode(timers), forKey: Self.entriesKey)
            } catch {
                Self.logger.error("Failed to save timers: \(error)")
            }
        }
    }
    var ringing: [LiveTimerEntry] { timers.filter { $0.status == .ringing } }
    var isRinging: Bool { !ringing.isEmpty }
    var nextTimer: LiveTimerEntry? { timers.first { $0.status == .running } }
    static let defaultDurations: [TimeInterval] = [300, 600, 900, 1500, 1800, 3600]
    var defaultDuration: TimeInterval {
        didSet { defaults.set(defaultDuration, forKey: "notchcast.liveTimer.defaultDuration") }
    }
    var playSoundWhenTimeIsUp: Bool {
        didSet {
            defaults.set(playSoundWhenTimeIsUp, forKey: Self.soundKey)
            refresh()
        }
    }

    private static let soundKey = "notchcast.liveTimer.playSound"
    private static let entriesKey = "notchcast.liveTimer.entries"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev",
                                       category: "LiveTimerStore")
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar
    @ObservationIgnored private let playSound: () -> Void
    @ObservationIgnored private let stopSound: () -> Void
    @ObservationIgnored private var wake: (any DispatchSourceTimer)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var nextSound: Date?
    @ObservationIgnored private var active: Bool

    init(defaults: UserDefaults = UserDefaults(
        suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!,
         clock: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
         playSound: (() -> Void)? = nil, stopSound: (() -> Void)? = nil, active: Bool = true) {
        self.defaults = defaults
        self.active = active
        let duration = defaults.double(forKey: "notchcast.liveTimer.defaultDuration")
        defaultDuration = Self.defaultDurations.contains(duration) ? duration : LiveTimerInput.defaultDuration
        self.clock = clock
        self.calendar = calendar
        let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: true)
        self.playSound = playSound ?? { sound?.play() }
        self.stopSound = stopSound ?? { sound?.stop() }
        playSoundWhenTimeIsUp = defaults.object(forKey: Self.soundKey) as? Bool ?? true
        if let data = defaults.data(forKey: Self.entriesKey) {
            do {
                timers = try JSONDecoder().decode([LiveTimerEntry].self, from: data)
            } catch {
                Self.logger.error("Failed to load timers: \(error)")
            }
        }
        refresh()
    }

    isolated deinit { wake?.cancel(); stopSound() }

    @discardableResult
    func start(_ seconds: TimeInterval? = nil, label: String = "") -> UUID? {
        let seconds = seconds ?? defaultDuration
        guard seconds.isFinite, (1...LiveTimerInput.maximumDuration).contains(seconds) else { return nil }
        return add(kind: .timer, end: clock().addingTimeInterval(seconds), label: label)
    }

    @discardableResult
    func startAlarm(_ text: String, label: String = "") -> UUID? {
        guard let end = LiveTimerInput.alarm(text, now: clock(), calendar: calendar()) else { return nil }
        return add(kind: .alarm, end: end, label: label)
    }

    func cancel(_ id: UUID) {
        timers.removeAll { $0.id == id }
        refresh()
    }

    func dismiss(_ id: UUID) {
        timers.removeAll { $0.id == id && ($0.status == .ringing || $0.status == .missed) }
        refresh()
    }

    func stop() {
        active = false
        generation = UUID()
        wake?.cancel()
        wake = nil
        nextSound = nil
        stopSound()
    }

    func refresh() {
        guard active else { return }
        generation = UUID()
        wake?.cancel()
        wake = nil
        let now = clock()
        for index in timers.indices where timers[index].end <= now {
            guard timers[index].status == .running || timers[index].status == .ringing else { continue }
            timers[index].status = now.timeIntervalSince(timers[index].end) >= 300 ? .missed : .ringing
        }
        if isRinging && playSoundWhenTimeIsUp {
            if nextSound.map({ $0 <= now }) ?? true {
                playSound()
                nextSound = now.addingTimeInterval(2)
            }
        } else {
            nextSound = nil
            stopSound()
        }
        schedule(now: now)
    }

    func resume() {
        active = true
        refresh()
    }

    private func add(kind: LiveTimerEntry.Kind, end: Date, label: String) -> UUID {
        let entry = LiveTimerEntry(id: UUID(), kind: kind, label: LiveTimerInput.label(label), end: end)
        timers.append(entry)
        timers.sort { $0.end < $1.end }
        refresh()
        return entry.id
    }

    private func schedule(now: Date) {
        var dates = timers.compactMap { entry -> Date? in
            switch entry.status {
            case .running: entry.end
            case .ringing: entry.end.addingTimeInterval(300)
            default: nil
            }
        }
        if let nextSound { dates.append(nextSound) }
        guard let date = dates.min() else { return }
        let token = generation
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(wallDeadline: .now() + max(0.001, date.timeIntervalSince(now)), leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.refresh()
            }
        }
        wake = source
        source.resume()
    }
}
