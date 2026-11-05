import Foundation
import Observation

@MainActor
@Observable
final class IslandActivityCenter {
    static let shared = IslandActivityCenter()

    var hasPresenter = false
    private(set) var activities: [IslandActivity] = []
    private(set) var message: IslandMessage?
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    @ObservationIgnored private let sleep: @MainActor (TimeInterval) async -> Void
    @ObservationIgnored private var pending: [Notice] = []
    @ObservationIgnored private var visibleID: String?

    private struct Notice {
        let id: String?
        let text: String
        let tone: IslandMessage.Tone
        let dwell: TimeInterval
    }

    init(sleep: @escaping @MainActor (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.sleep = sleep
    }

    var current: IslandActivity? {
        activities.reduce(nil) { best, next in
            guard let best else { return next }
            return next.outranks(best) ? next : best
        }
    }

    @discardableResult
    func begin(_ activity: IslandActivity) -> UUID {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        return activity.id
    }

    func update(_ id: UUID, title: String? = nil, progress: Double?? = nil,
                endDate: Date?? = nil, priority: Int? = nil) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        if let title { activities[index].title = title }
        if let progress { activities[index].progress = progress.map { min(max($0, 0), 1) } }
        if let endDate { activities[index].endDate = endDate }
        if let priority { activities[index].priority = priority }
    }

    func finish(_ id: UUID) { activities.removeAll { $0.id == id } }

    func fail(_ id: UUID) { finish(id) }

    /// Only an `id` waits its turn; without one a message replaces the visible one, like upstream's HUD.
    func showMessage(_ text: String, tone: IslandMessage.Tone, dwell: TimeInterval, id: String? = nil) {
        let notice = Notice(id: id, text: text, tone: tone, dwell: dwell)
        guard let id, message != nil, id != visibleID else { return present(notice) }
        if let index = pending.firstIndex(where: { $0.id == id }) {
            pending[index] = notice
        } else {
            pending.append(notice)
            if pending.count > 8 { pending.removeFirst() }
        }
    }

    private func present(_ notice: Notice) {
        dismissal?.cancel()
        visibleID = notice.id
        message = IslandMessage(id: message?.id ?? UUID(), tone: notice.tone, text: notice.text,
                                isProgress: false, onCancel: nil)
        dismissal = Task { [weak self, sleep] in
            await sleep(notice.dwell)
            guard !Task.isCancelled else { return }
            self?.dismissMessage()
        }
    }

    func showProgress(_ text: String, onCancel: (() -> Void)? = nil) {
        dismissal?.cancel()
        visibleID = nil
        message = IslandMessage(id: message?.id ?? UUID(), tone: .neutral, text: text, isProgress: true,
                                onCancel: onCancel)
    }

    /// Ends only the visible message; waiting notices keep their turn.
    func dismissMessage() {
        dismissal?.cancel()
        dismissal = nil
        visibleID = nil
        message = nil
        if !pending.isEmpty { present(pending.removeFirst()) }
    }
}
