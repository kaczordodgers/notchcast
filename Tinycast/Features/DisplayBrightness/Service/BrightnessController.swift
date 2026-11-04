import AppKit
import Foundation
import Observation

@MainActor @Observable
final class BrightnessController {
    enum StepResult: Sendable {
        case applied(BrightnessLevel), unavailable, cancelled
    }

    private(set) var currentDisplays: [BrightnessDisplay] = []

    @ObservationIgnored private let service = BrightnessDisplayService()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var appliedRevision = 0
    @ObservationIgnored private var tail: Task<[BrightnessDisplay]?, Never>?
    @ObservationIgnored private var operations: [UUID: Task<[BrightnessDisplay]?, Never>] = [:]
    @ObservationIgnored private var screenTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    isolated deinit {
        screenTask?.cancel()
        wakeTask?.cancel()
        refreshTask?.cancel()
        for task in operations.values { task.cancel() }
    }

    func displays() -> [BrightnessDisplay] { currentDisplays }

    func level(of display: BrightnessDisplay.ID) -> BrightnessLevel? {
        currentDisplays.first(where: { $0.id == display })?.level
    }

    func start() async {
        guard !running, !stopping else { return }
        running = true
        screenTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification).map({ _ in true }) {
                guard !Task.isCancelled else { return }
                self?.scheduleRefresh()
            }
        }
        wakeTask = Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.screensDidWakeNotification).map({ _ in true }) {
                guard !Task.isCancelled else { return }
                self?.scheduleRefresh()
            }
        }
        await refresh()
    }

    func refresh() async {
        let names = Dictionary(NSScreen.screens.compactMap { screen -> (UInt32, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return (number.uint32Value, screen.localizedName)
        }, uniquingKeysWith: { first, _ in first })
        _ = await perform(.refresh(names: names))
    }

    @discardableResult
    func set(_ value: Double, for display: BrightnessDisplay.ID) async -> BrightnessLevel? {
        await perform(.set(value, display))?.first(where: { $0.id == display })?.level
    }

    @discardableResult
    func step(up: Bool, fine: Bool, for display: BrightnessDisplay.ID) async -> StepResult {
        let epoch = generation
        let request = revision + 1
        let result = await perform(.step(up: up, fine: fine, display))
        guard !Task.isCancelled, running, generation == epoch, request >= appliedRevision
        else { return .cancelled }
        guard let level = result?.first(where: { $0.id == display })?.level else { return .unavailable }
        return .applied(level)
    }

    func stop() async {
        guard !stopping else { return }
        stopping = true
        running = false
        generation += 1
        let stoppedGeneration = generation
        screenTask?.cancel()
        wakeTask?.cancel()
        refreshTask?.cancel()
        screenTask = nil
        wakeTask = nil
        refreshTask = nil
        let pending = Array(operations.values)
        for task in pending { task.cancel() }
        for task in pending { _ = await task.value }
        await service.stop()
        guard generation == stoppedGeneration else { return }
        operations = [:]
        tail = nil
        currentDisplays = []
        stopping = false
    }

    private func perform(_ operation: BrightnessDisplayService.Operation) async -> [BrightnessDisplay]? {
        guard running, !Task.isCancelled else { return nil }
        let token = UUID()
        let epoch = generation
        revision += 1
        let request = revision
        let predecessor = tail
        let service = service
        let task = Task {
            _ = await predecessor?.value
            guard !Task.isCancelled else { return nil as [BrightnessDisplay]? }
            return await service.perform(operation)
        }
        operations[token] = task
        tail = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        operations[token] = nil
        guard running, generation == epoch else { return nil }
        if request > appliedRevision, let result {
            appliedRevision = request
            currentDisplays = result
        }
        guard !Task.isCancelled, request >= appliedRevision else { return nil }
        return result
    }

    private func scheduleRefresh() {
        guard running else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await self?.refresh()
        }
    }
}
