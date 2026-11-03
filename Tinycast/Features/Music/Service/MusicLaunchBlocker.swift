// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Observation

@MainActor
@Observable
final class MusicLaunchBlocker {
    enum Failure: Equatable, Sendable {
        case couldNotQuit
    }

    private(set) var isEnabled = false
    private(set) var failure: Failure?
    @ObservationIgnored private let apps: PlayerApps
    @ObservationIgnored private let uptime: @MainActor () -> TimeInterval
    @ObservationIgnored private let gestureAge: @MainActor () -> TimeInterval
    @ObservationIgnored private let openReplacement: @MainActor (Bool) -> Task<Void, Never>
    @ObservationIgnored private var observations: [NotificationToken] = []
    @ObservationIgnored private var keyAt: TimeInterval?
    @ObservationIgnored private var key: MusicLaunchPolicy.MediaKey?
    @ObservationIgnored private var judgedProcessID: pid_t?
    @ObservationIgnored private var replacement: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(apps: PlayerApps = .workspace(),
         uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         gestureAge: @escaping @MainActor () -> TimeInterval = MusicLaunchBlocker.secondsSinceGesture,
         openReplacement: @escaping @MainActor (Bool) -> Task<Void, Never>) {
        self.apps = apps
        self.uptime = uptime
        self.gestureAge = gestureAge
        self.openReplacement = openReplacement
    }

    isolated deinit { replacement?.cancel() }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        generation += 1
        keyAt = nil
        key = nil
        judgedProcessID = nil
        failure = nil
        replacement?.cancel()
        replacement = nil
        observations = []
        if enabled {
            let generation = generation
            observations = apps.watchLaunches { [weak self] launch in
                guard let self, self.generation == generation else { return }
                launched(launch)
            }
        }
    }

    func noteMediaKey(_ key: MusicLaunchPolicy.MediaKey) {
        noteMediaKey(key, at: uptime())
    }

    func noteMediaKey(_ key: MusicLaunchPolicy.MediaKey, at timestamp: TimeInterval) {
        guard isEnabled else { return }
        keyAt = apps.isRunning(LastPlayer.appleMusic) ? nil : timestamp
        self.key = key
    }

    private func launched(_ launch: PlayerApps.Launch) {
        guard isEnabled, launch.bundleID == LastPlayer.appleMusic,
            launch.processID > 0, launch.processID != judgedProcessID else { return }
        judgedProcessID = launch.processID
        let trigger = keyAt
        keyAt = nil
        guard MusicLaunchPolicy.shouldBlock(now: uptime(), keyAt: trigger, gestureAge: gestureAge()) else { return }
        guard apps.quit(launch) else {
            failure = .couldNotQuit
            return
        }
        failure = nil
        let shouldPlay = key == .playPause
        replacement?.cancel()
        replacement = openReplacement(shouldPlay)
    }

    static func secondsSinceGesture() -> TimeInterval {
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .keyDown
        ]
        return types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? .infinity
    }
}
