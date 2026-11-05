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

    /// A message shown while another is up replaces it in place and re-arms the dwell, like upstream's HUD.
    func showMessage(_ text: String, tone: IslandMessage.Tone, dwell: TimeInterval) {
        dismissal?.cancel()
        message = IslandMessage(id: message?.id ?? UUID(), tone: tone, text: text, isProgress: false, onCancel: nil)
        dismissal = Task { [weak self, sleep] in
            await sleep(dwell)
            guard !Task.isCancelled else { return }
            self?.dismissMessage()
        }
    }

    func showProgress(_ text: String, onCancel: (() -> Void)? = nil) {
        dismissal?.cancel()
        message = IslandMessage(id: message?.id ?? UUID(), tone: .neutral, text: text, isProgress: true,
                                onCancel: onCancel)
    }

    func dismissMessage() {
        dismissal?.cancel()
        dismissal = nil
        message = nil
    }
}
