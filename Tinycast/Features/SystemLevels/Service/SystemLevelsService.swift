import Foundation
import Observation

@MainActor @Observable
final class SystemLevelsService {
    enum Command: Sendable {
        case step(increasing: Bool, fine: Bool = false)
        case setVolume(Double)
        case setMuted(Bool)
        case toggleMute
    }

    enum Result: Sendable, Equatable {
        case applied(LevelNotice)
        case fallbackToNativeKeys
        case cancelled
    }

    private(set) var state = SystemAudioState()
    private(set) var isRunning = false
    var onLevelChange: ((LevelNotice) -> Void)?
    @ObservationIgnored private let hardware: any SystemAudioHardware
    @ObservationIgnored private let monitor: SystemAudioMonitor?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var readAgain = false
    @ObservationIgnored private var operations: [UUID: Task<Result, Never>] = [:]
    @ObservationIgnored private var tail: Task<Result, Never>?
    @ObservationIgnored private var tailID: UUID?
    @ObservationIgnored private var pendingStep: UUID?

    init(hardware: any SystemAudioHardware = CoreAudioLevelAccess(), observeHardware: Bool = true) {
        self.hardware = hardware
        monitor = observeHardware ? SystemAudioMonitor() : nil
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        monitor?.start(state: state) { [weak self] in self?.refresh() }
        refresh()
    }

    func stop() {
        isRunning = false
        generation = UUID()
        monitor?.stop()
        reading?.cancel()
        reading = nil
        readAgain = false
        for operation in operations.values { operation.cancel() }
        operations = [:]
        tail = nil
        tailID = nil
        pendingStep = nil
        state = SystemAudioState()
    }

    func refresh() {
        guard isRunning else { return }
        guard reading == nil else { readAgain = true; return }
        let current = generation
        reading = Task { [weak self, hardware] in
            let next = await Self.read(hardware)
            guard !Task.isCancelled, let self, self.generation == current, self.isRunning else { return }
            self.reading = nil
            let previous = self.state
            self.state = next
            if previous.output?.device != next.output?.device || previous.microphone?.device != next.microphone?.device {
                self.monitor?.start(state: next) { [weak self] in self?.refresh() }
            }
            for notice in next.changes(from: previous) { self.onLevelChange?(notice) }
            if self.readAgain {
                self.readAgain = false
                self.refresh()
            }
        }
    }

    func apply(_ command: Command) async -> Result {
        if case .step = command, let pendingStep {
            operations[pendingStep]?.cancel()
        }
        let current = generation
        let id = UUID()
        let previous = tail
        let task = Task { [weak self, hardware] in
            _ = await previous?.value
            guard !Task.isCancelled else { return Result.cancelled }
            if self?.pendingStep == id { self?.pendingStep = nil }
            return await Self.adjust(command, hardware: hardware)
        }
        if case .step = command { pendingStep = id }
        operations[id] = task
        tail = task
        tailID = id
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        operations[id] = nil
        if tailID == id { tail = nil; tailID = nil }
        guard !Task.isCancelled, generation == current else { return .cancelled }
        refresh()
        return result
    }

    func settled() async {
        while let reading { await reading.value }
    }

    @concurrent
    private static func read(_ hardware: any SystemAudioHardware) async -> SystemAudioState {
        .init(output: hardware.output(), microphone: hardware.microphone())
    }

    @concurrent
    private static func adjust(_ command: Command, hardware: any SystemAudioHardware) async -> Result {
        guard !Task.isCancelled, let initial = hardware.output() else { return .fallbackToNativeKeys }
        switch command {
        case .setMuted(let muted):
            return await mute(muted, initial: initial, hardware: hardware)
        case .toggleMute:
            guard let muted = initial.muted else { return .fallbackToNativeKeys }
            return await mute(!muted, initial: initial, hardware: hardware)
        case .setVolume(let value):
            guard value.isFinite, (0...1).contains(value) else { return .fallbackToNativeKeys }
            return await volume([value], initial: initial, increasing: nil, hardware: hardware)
        case .step(let increasing, let fine):
            guard let level = initial.volume else { return .fallbackToNativeKeys }
            let candidates = VolumeStepPolicy.candidates(from: level, increasing: increasing, fine: fine)
            let result = await volume(candidates, initial: initial, increasing: increasing, hardware: hardware)
            if increasing, initial.muted == true, case .applied = result, let next = hardware.output(),
               next.device == initial.device {
                return await mute(false, initial: next, hardware: hardware)
            }
            return result
        }
    }

    @concurrent
    private static func volume(_ candidates: [Double], initial: SystemAudioState.Output,
                               increasing: Bool?, hardware: any SystemAudioHardware) async -> Result {
        guard let original = initial.volume else { return .fallbackToNativeKeys }
        for candidate in candidates {
            guard !Task.isCancelled else { return .cancelled }
            guard hardware.output()?.device == initial.device else { return .cancelled }
            if abs(candidate - original) <= VolumeStepPolicy.tolerance { return .applied(initial.notice) }
            guard hardware.writeVolume(candidate, device: initial.device) else { return .fallbackToNativeKeys }
            for _ in 0..<4 {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return .cancelled }
                guard let next = hardware.output(), next.device == initial.device else { return .cancelled }
                guard let level = next.volume else { return .fallbackToNativeKeys }
                let directAccepted = abs(candidate - level) <= VolumeStepPolicy.tolerance
                    || abs(level - original) > VolumeStepPolicy.tolerance
                let accepted = increasing.map { VolumeStepPolicy.advanced(from: original, to: level, increasing: $0) }
                    ?? directAccepted
                if accepted { return .applied(next.notice) }
            }
        }
        return .fallbackToNativeKeys
    }

    @concurrent
    private static func mute(_ value: Bool, initial: SystemAudioState.Output,
                             hardware: any SystemAudioHardware) async -> Result {
        guard !Task.isCancelled else { return .cancelled }
        guard initial.muted != nil, hardware.output()?.device == initial.device else { return .fallbackToNativeKeys }
        if initial.muted == value { return .applied(initial.notice) }
        guard hardware.writeMute(value, device: initial.device) else { return .fallbackToNativeKeys }
        for _ in 0..<4 {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return .cancelled }
            guard let next = hardware.output(), next.device == initial.device else { return .cancelled }
            if next.muted == value { return .applied(next.notice) }
        }
        return .fallbackToNativeKeys
    }

    isolated deinit {
        monitor?.stop()
        reading?.cancel()
        for operation in operations.values { operation.cancel() }
    }
}
