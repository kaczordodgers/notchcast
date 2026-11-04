import Foundation

extension FanControl {
    func applyAndWait(_ requested: Mode) async throws -> Mode {
        set(requested)
        await waitUntilIdle()
        try Task.checkCancellation()
        if let failure { throw failure }
        guard mode == requested, !unavailable else { throw RemoteFanReport.Failure.busy }
        return mode
    }
}
