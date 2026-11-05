import Foundation

@MainActor
final class SystemLevelIslandPresenter {
    private let center: IslandActivityCenter
    private let id = UUID()
    private var dismissal: Task<Void, Never>?

    init(center: IslandActivityCenter) {
        self.center = center
    }

    func present(_ notice: LevelNotice?) {
        dismissal?.cancel()
        dismissal = nil
        guard let notice else {
            center.finish(id)
            return
        }
        let title = notice.kind == .brightness
            ? String(localized: "Brightness", table: "Notchcast") : String(localized: "Volume")
        center.begin(IslandActivity(id: id, kind: .status, priority: 100, title: title,
                                   progress: notice.muted == true ? 0 : notice.percent.map { Double($0) / 100 }))
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            center.finish(id)
            dismissal = nil
        }
    }
}
