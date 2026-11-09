import Foundation
import Observation

@MainActor
@Observable
final class IslandActivityCenter {
    static let shared = IslandActivityCenter()

    /// Identifies one posted notice, so its poster can end it and nobody else's.
    struct NoticeHandle: Hashable, Sendable {
        fileprivate let id = UUID()
    }

    var hasPresenter = false
    private(set) var activities: [IslandActivity] = []
    private(set) var message: IslandMessage?
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    @ObservationIgnored private let sleep: @MainActor (TimeInterval) async -> Void
    @ObservationIgnored private var pending: [Notice] = []
    @ObservationIgnored private var visibleID: String?
    @ObservationIgnored private var visibleOwner: NoticeHandle?

    private struct Notice {
        let id: String?
        let text: String
        let tone: IslandMessage.Tone
        let dwell: TimeInterval
        let symbol: String?
        let owner = NoticeHandle()
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

    /// Every activity, the one that outranks the rest first.
    var ranked: [IslandActivity] {
        activities.sorted { $0.outranks($1) }
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
                endDate: Date?? = nil, priority: Int? = nil, value: IslandValue?? = nil) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        if let value { activities[index].value = value.map(IslandValue.clamped) }
        if let title { activities[index].title = title }
        if let progress { activities[index].progress = progress.map { min(max($0, 0), 1) } }
        if let endDate { activities[index].endDate = endDate }
        if let priority { activities[index].priority = priority }
    }

    func finish(_ id: UUID) { activities.removeAll { $0.id == id } }

    func fail(_ id: UUID) { finish(id) }

    /// Only an `id` waits its turn; without one a message replaces the visible one, like upstream's HUD.
    @discardableResult
    func showMessage(_ text: String, tone: IslandMessage.Tone, dwell: TimeInterval,
                     id: String? = nil, symbol: String? = nil) -> NoticeHandle {
        let notice = Notice(id: id, text: text, tone: tone, dwell: dwell, symbol: symbol)
        guard let id, message != nil, id != visibleID else {
            present(notice)
            return notice.owner
        }
        if let index = pending.firstIndex(where: { $0.id == id }) {
            pending[index] = notice
        } else {
            pending.append(notice)
            if pending.count > 8 { pending.removeFirst() }
        }
        return notice.owner
    }

    private func present(_ notice: Notice) {
        dismissal?.cancel()
        visibleID = notice.id
        visibleOwner = notice.owner
        message = IslandMessage(id: message?.id ?? UUID(), tone: notice.tone, text: notice.text,
                                isProgress: false, onCancel: nil, symbol: notice.symbol)
        dismissal = Task { [weak self, sleep] in
            await sleep(notice.dwell)
            guard !Task.isCancelled else { return }
            self?.dismissMessage()
        }
    }

    @discardableResult
    func showProgress(_ text: String, onCancel: (() -> Void)? = nil) -> NoticeHandle {
        dismissal?.cancel()
        visibleID = nil
        let owner = NoticeHandle()
        visibleOwner = owner
        message = IslandMessage(id: message?.id ?? UUID(), tone: .neutral, text: text, isProgress: true,
                                onCancel: onCancel)
        return owner
    }

    /// Ends `notice` only while it is still its poster's; a replaced or finished one is left alone.
    func dismiss(_ notice: NoticeHandle) {
        guard visibleOwner == notice else { return pending.removeAll { $0.owner == notice } }
        dismissMessage()
    }

    /// Ends only the visible message; waiting notices keep their turn.
    private func dismissMessage() {
        dismissal?.cancel()
        dismissal = nil
        visibleID = nil
        visibleOwner = nil
        message = nil
        if !pending.isEmpty { present(pending.removeFirst()) }
    }
}
