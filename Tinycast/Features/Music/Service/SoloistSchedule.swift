import Foundation

@MainActor
final class SoloistCancellation {
    private var action: (() -> Void)?

    init(_ action: @escaping () -> Void) { self.action = action }

    func cancel() {
        let action = action
        self.action = nil
        action?()
    }

    isolated deinit { action?() }
}

@MainActor
struct SoloistSchedule {
    var now: () -> TimeInterval
    var after: (TimeInterval, @escaping @MainActor () -> Void) -> SoloistCancellation

    static var live: Self {
        Self(now: { ProcessInfo.processInfo.systemUptime }, after: { delay, action in
            let task = Task {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled else { return }
                action()
            }
            return SoloistCancellation { task.cancel() }
        })
    }
}
