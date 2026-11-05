import Foundation

@MainActor
final class SystemLevelIslandPresenter {
    private let center: IslandActivityCenter
    private let id = UUID()
    private var dismissal: Task<Void, Never>?

    init(center: IslandActivityCenter) {
        self.center = center
    }

    /// Glyph left, percent right (look-decisions, Volume): a muted level shows the slashed glyph and "Off".
    func present(_ notice: LevelNotice?) {
        dismissal?.cancel()
        dismissal = nil
        guard let notice else {
            center.finish(id)
            return
        }
        let title = switch notice.kind {
        case .brightness: String(localized: "Brightness", table: "Notchcast")
        case .microphone: String(localized: "Microphone")
        case .volume: String(localized: "Volume")
        }
        let value: IslandActivity.Value? = notice.muted == true ? .onOff(false)
            : notice.percent.map { .percent(Double($0) / 100) }
        center.begin(IslandActivity(id: id, kind: .status, priority: 100, title: title, symbol: notice.symbol,
                                   value: value))
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            center.finish(id)
            dismissal = nil
        }
    }
}
