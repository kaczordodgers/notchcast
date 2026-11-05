import Observation

@MainActor
@Observable
final class NotchcastGrantState {
    private(set) var values: [NotchcastGrant: Bool] = [:]
    @ObservationIgnored private var refreshID = 0

    func refresh(_ grants: [NotchcastGrant]) async {
        refreshID += 1
        let operation = refreshID
        var updated: [NotchcastGrant: Bool] = [:]
        for grant in grants {
            updated[grant] = await grant.readIsGranted()
            guard !Task.isCancelled, operation == refreshID else { return }
        }
        values.merge(updated) { _, new in new }
    }
}
