import Observation

/// Started once all of its entry's required switches are on and stopped when one turns off. Other
/// switch flips never restart it: a module reads its own sub-switches live through Observation.
@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor
final class NotchcastModuleController {
    struct Entry {
        let requires: [NotchcastFeature]
        let module: any NotchcastModule
    }

    private let entries: [Entry]
    private let preferences: NotchcastPreferences
    private var running: Set<Int> = []

    init(_ entries: [Entry], preferences: NotchcastPreferences) {
        self.entries = entries
        self.preferences = preferences
    }

    /// Applies the switches now and again after every change to one the entries read.
    func run() {
        withObservationTracking(update) { [weak self] in
            // Fires before the new value is stored, so the re-run waits for the main actor's next turn.
            Task { @MainActor [weak self] in self?.run() }
        }
    }

    private func update() {
        for (index, entry) in entries.enumerated() {
            let enabled = entry.requires.allSatisfy(preferences.isOn)
            if enabled && running.insert(index).inserted {
                entry.module.start()
            } else if !enabled && running.remove(index) != nil {
                entry.module.stop()
            }
        }
    }
}
