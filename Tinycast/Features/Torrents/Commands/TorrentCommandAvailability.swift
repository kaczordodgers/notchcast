import Observation

@MainActor
final class TorrentCommandAvailability {
    private var previous: Bool?

    init() { observe() }

    private func observe() {
        withObservationTracking {
            let current = NotchcastPreferences.shared.isOn(.torrents)
            if let previous, previous != current { AppCore.shared.appIndex.refreshNotchcastCommands() }
            previous = current
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
}
