import AppKit

extension TreadmillCoordinator {
    nonisolated static let stopCommand = NotchcastCommand(
        slug: "treadmill-stop", name: String(localized: "Treadmill: Stop"), sfSymbol: "stop.fill",
        isEnabled: { NotchcastPreferences.shared.isOn(.treadmillWalk) },
        run: { NotchcastCore.treadmill.runCommand(start: false) })

    nonisolated static let startCommand = NotchcastCommand(
        slug: "treadmill-start-walk", name: String(localized: "Treadmill: Start Walk"), sfSymbol: "figure.walk",
        isEnabled: { NotchcastPreferences.shared.isOn(.treadmillWalk) },
        run: { NotchcastCore.treadmill.runCommand(start: true) })

    @discardableResult
    func runCommand(start: Bool,
                    enabled: @escaping () -> Bool = { NotchcastPreferences.shared.isOn(.treadmillWalk) },
                    confirm: @escaping @MainActor () async -> Bool = confirmStart,
                    message: @escaping (String, DialogTone) -> Void = {
                        AppCore.shared.showMessage($0, tone: $1)
                    }) -> Task<Void, Never>? {
        guard enabled() else { return nil }
        if start, commandTask != nil { return nil }
        if !start { commandTask?.cancel() }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if start { self.commandTask = nil } }
            if start, !(await confirm()) { return }
            guard !Task.isCancelled, enabled() else { return }
            do {
                if start { try self.startWalk() } else { try self.stopWalk() }
                message(String(localized: "Treadmill command sent."), .success)
            } catch {
                message(error.localizedDescription, .danger)
            }
        }
        if start { commandTask = task }
        return task
    }
}
