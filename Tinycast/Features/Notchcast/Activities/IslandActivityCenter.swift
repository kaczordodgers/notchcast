import Foundation
import Observation

@MainActor
@Observable
final class IslandActivityCenter {
    static let shared = IslandActivityCenter()

    weak var presenter: (any IslandActivityPresenter)?
    private(set) var activities: [IslandActivity] = []
    private(set) var message: IslandMessage?
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    var current: IslandActivity? {
        activities.reduce(nil) { best, next in
            guard let best else { return next }
            return next.outranks(best) ? next : best
        }
    }

    deinit { dismissal?.cancel() }

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

    func showMessage(_ text: String, tone: IslandMessage.Tone, dwell: TimeInterval) {
        dismissMessage()
        let message = IslandMessage(tone: tone, text: text, isProgress: false, onCancel: nil)
        self.message = message
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(dwell)) } catch { return }
            guard !Task.isCancelled, self?.message?.id == message.id else { return }
            self?.dismissMessage()
        }
    }

    func showProgress(_ text: String, onCancel: (() -> Void)? = nil) {
        dismissMessage()
        message = IslandMessage(tone: .neutral, text: text, isProgress: true, onCancel: onCancel)
    }

    func dismissMessage() {
        dismissal?.cancel()
        dismissal = nil
        message = nil
    }
}
