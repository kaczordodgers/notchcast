import Foundation
import Observation

@MainActor @Observable
final class FleetModule: NotchcastModule {
    private(set) var isEnabled = false
    private(set) var model: FleetModel?

    func configure(source: any FleetThreadSource, destinations: [FleetSnapshot.Destination], clock: @escaping () -> Date) {
        model?.invalidate()
        model = FleetModel(source: source, destinations: destinations, clock: clock)
    }

    func start() { isEnabled = true }

    func stop() {
        isEnabled = false
        model?.invalidate()
    }

    func refresh() async {
        guard isEnabled else { return }
        await model?.refresh()
    }
}

