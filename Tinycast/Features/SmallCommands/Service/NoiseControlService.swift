import Foundation

struct NoiseControlService: Sendable {
    enum Outcome: Equatable, Sendable {
        case switched(NoiseControlEngine.Mode)
        case noAirPods
        case unchanged
    }
    enum Failure: LocalizedError {
        case needsAccessibility

        var errorDescription: String? {
            String(localized: "Allow Accessibility access to switch noise control.", table: "Notchcast")
        }
    }

    enum Action: Equatable, Sendable {
        case open
        case snapshot
        case press(NoiseControlEngine.Mode)
        case close
    }

    typealias Perform = @Sendable (Action, Duration) async throws -> [NoiseControlEngine.Button]
    private let perform: Perform
    private let sleep: @Sendable () async throws -> Void
    private let now: @Sendable () -> Duration

    init(processID: Int32) {
        self.init { action, deadline in
            try await NoiseControlSystem.perform(action, processID: processID, deadline: deadline)
        }
    }

    init(
        perform: @escaping Perform,
        sleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(50)) },
        now: @escaping @Sendable () -> Duration = {
            .seconds(ProcessInfo.processInfo.systemUptime)
        }
    ) {
        self.perform = perform
        self.sleep = sleep
        self.now = now
    }

    func switchMode() async throws -> Outcome {
        try Task.checkCancellation()
        let deadline = now() + .seconds(8)
        var opened = false
        do {
            _ = try await perform(.open, deadline)
            opened = true
            let result = try await switchMode(deadline: deadline)
            _ = try await perform(.close, now() + .seconds(1))
            opened = false
            try Task.checkCancellation()
            return result
        } catch {
            if opened { _ = try? await perform(.close, now() + .seconds(1)) }
            throw error
        }
    }

    private func switchMode(deadline: Duration) async throws -> Outcome {
        for _ in 0..<160 {
            try Task.checkCancellation()
            guard now() < deadline else { return .unchanged }
            let buttons = try await perform(.snapshot, deadline)
            if buttons.isEmpty {
                try await sleep()
                continue
            }
            guard let target = NoiseControlEngine.target(in: buttons) else { return .noAirPods }
            try Task.checkCancellation()
            guard now() < deadline else { return .unchanged }
            _ = try await perform(.press(target), deadline)
            guard buttons.contains(where: { $0.selected != nil }) else { return .switched(target) }
            for _ in 0..<160 {
                try await sleep()
                try Task.checkCancellation()
                guard now() < deadline else { return .unchanged }
                let updated = try await perform(.snapshot, deadline)
                if updated.contains(where: { $0.mode == target && $0.selected == true }) {
                    return .switched(target)
                }
            }
            return .unchanged
        }
        return .noAirPods
    }
}
