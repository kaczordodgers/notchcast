import Foundation
import Observation

@MainActor @Observable
final class InUseMarks {
    typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)

    private(set) var camera = false
    private(set) var microphone = false
    private(set) var micApps: [String] = []
    private(set) var failure: MicrophoneInput.Failure?
    private(set) var isEnabled = false
    var isMuted: Bool { isEnabled && muted() }

    @ObservationIgnored private let source: any InUseSource
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let schedule: Schedule
    @ObservationIgnored private let muted: () -> Bool
    @ObservationIgnored private var lastRead: TimeInterval?
    @ObservationIgnored private var cancelPending: (() -> Void)?
    @ObservationIgnored private var generation = 0

    init(source: any InUseSource, now: @escaping () -> TimeInterval,
         schedule: @escaping Schedule, isMuted: @escaping () -> Bool) {
        self.source = source
        self.now = now
        self.schedule = schedule
        muted = isMuted
    }

    isolated deinit {
        cancelPending?()
        source.stop()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        generation += 1
        isEnabled = enabled
        guard enabled else {
            cancelPending?()
            cancelPending = nil
            source.stop()
            camera = false
            microphone = false
            micApps = []
            failure = nil
            return
        }
        let identity = generation
        source.start { [weak self] in
            guard let self, self.generation == identity else { return }
            self.changed()
        }
        changed()
    }

    private func changed() {
        guard isEnabled, cancelPending == nil else { return }
        let delay = (lastRead.map { $0 + 1 } ?? now()) - now()
        guard delay > 0 else {
            read()
            return
        }
        let identity = generation
        cancelPending = schedule(delay) { [weak self] in
            guard let self, self.isEnabled, self.generation == identity else { return }
            self.cancelPending = nil
            self.read()
        }
    }

    private func read() {
        lastRead = now()
        do {
            let reading = try source.read()
            camera = reading.camera
            microphone = reading.microphone
            micApps = Array(Set(reading.micApps.filter { !$0.isEmpty })).sorted()
            failure = source.monitoringFailure
        } catch {
            failure = error
            camera = false
            microphone = false
            micApps = []
        }
    }
}
