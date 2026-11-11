import Observation

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor
final class NotchcastModuleController {
    struct Entry {
        let requires: [NotchcastFeature]
        var requiresAny: [NotchcastFeature] = []
        let module: any NotchcastModule
    }

    private let entries: [Entry]
    private let preferences: NotchcastPreferences
    private let modulesChanged: @MainActor () -> Void
    private var running: Set<Int> = []

    init(_ entries: [Entry], preferences: NotchcastPreferences, modulesChanged: @escaping @MainActor () -> Void = {}) {
        self.entries = entries
        self.preferences = preferences
        self.modulesChanged = modulesChanged
    }

    /// Applies the switches now and again after every change to one the entries read.
    func run() {
        withObservationTracking(update) { [weak self] in
            // Fires before the new value is stored, so the re-run waits for the main actor's next turn.
            Task { @MainActor [weak self] in self?.run() }
        }
    }

    private func update() {
        let before = running
        for (index, entry) in entries.enumerated() {
            let enabled = entry.requires.allSatisfy(preferences.isOn)
                && (entry.requiresAny.isEmpty || entry.requiresAny.contains(where: preferences.isOn))
            if enabled && running.insert(index).inserted {
                entry.module.start()
            } else if !enabled && running.remove(index) != nil {
                entry.module.stop()
            }
        }
        if running != before { modulesChanged() }
    }
}
