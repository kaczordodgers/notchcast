import Foundation

extension InUseMarks {
    convenience init(source: any InUseSource = SystemInUseSource(), isMuted: @escaping () -> Bool) {
        self.init(source: source, now: { ProcessInfo.processInfo.systemUptime }, schedule: { delay, action in
            let task = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(delay))
                    try Task.checkCancellation()
                    action()
                } catch is CancellationError {
                    return
                } catch {
                    preconditionFailure("Unexpected clock failure: \(error)")
                }
            }
            return { task.cancel() }
        }, isMuted: isMuted)
    }
}
