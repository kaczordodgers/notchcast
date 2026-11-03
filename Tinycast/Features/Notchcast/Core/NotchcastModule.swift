@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor
final class NotchcastModuleController {
    struct Entry {
        let feature: NotchcastFeature
        let module: any NotchcastModule
    }

    private let entries: [Entry]
    private var running: Set<Int> = []

    init(_ entries: [Entry]) { self.entries = entries }

    func update(_ preferences: NotchcastPreferences) {
        for (index, entry) in entries.enumerated() {
            let enabled = preferences.isOn(.island) && preferences.isOn(entry.feature)
            if enabled && running.insert(index).inserted {
                entry.module.start()
            } else if !enabled && running.remove(index) != nil {
                entry.module.stop()
            }
        }
    }
}
