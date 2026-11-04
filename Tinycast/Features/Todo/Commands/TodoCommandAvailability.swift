import Observation

@MainActor
final class TodoCommandAvailability {
    private let preferences: NotchcastPreferences
    private let refresh: () -> Void

    init(preferences: NotchcastPreferences, refresh: @escaping () -> Void) {
        self.preferences = preferences
        self.refresh = refresh
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = preferences.isEnabled(.tasks)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        refresh()
    }
}
