import Foundation
import Synchronization

final class FinderShortcutState: Sendable {
    struct Request: Sendable {
        let action: FinderShortcutPolicy.Action
        let pid: Int32
        let generation: UUID
        let cutID: UUID
    }

    private struct State {
        var policy = FinderShortcutPolicy()
        var pid: Int32?
        var generation = UUID()
        var cutID = UUID()
    }

    private let state = Mutex(State())

    func configure(cut: Bool, rename: Bool, pid: Int32?) {
        state.withLock {
            $0.policy.cutEnabled = cut
            $0.policy.renameEnabled = rename
            $0.policy.reset()
            $0.pid = pid
            $0.generation = UUID()
            $0.cutID = UUID()
        }
    }

    func setFrontmostFinder(_ pid: Int32?) {
        state.withLock {
            guard $0.pid != pid else { return }
            $0.pid = pid
            $0.generation = UUID()
        }
    }

    func receive(_ event: FinderShortcutPolicy.Event) -> (FinderShortcutPolicy.Decision, Request?) {
        state.withLock {
            let decision = $0.policy.decide(event, inFinder: $0.pid != nil)
            guard case .perform(let action) = decision else { return (decision, nil) }
            if action == .cut || action == .forget { $0.cutID = UUID() }
            return (decision, Request(action: action, pid: $0.pid ?? 0,
                                      generation: $0.generation, cutID: $0.cutID))
        }
    }

    func isCurrent(_ request: Request) -> Bool {
        state.withLock {
            $0.generation == request.generation && $0.pid == request.pid
                && (request.action == .rename || $0.cutID == request.cutID)
        }
    }

    func isCurrentCut(_ request: Request) -> Bool {
        state.withLock { $0.cutID == request.cutID }
    }

    func finishCut(_ request: Request) {
        state.withLock {
            guard $0.generation == request.generation, $0.cutID == request.cutID else { return }
            $0.policy.forget()
        }
    }

    func restoreCut(_ request: Request) {
        state.withLock {
            guard $0.generation == request.generation, $0.cutID == request.cutID else { return }
            $0.policy.restoreCut()
        }
    }

    func forgetCut() {
        state.withLock {
            $0.policy.forget()
            $0.cutID = UUID()
        }
    }
}
