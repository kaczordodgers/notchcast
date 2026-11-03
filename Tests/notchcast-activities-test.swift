import Foundation

enum DialogTone { case neutral, success, danger }
enum Theme {
    enum Duration { static let messageHUD: TimeInterval = 2.4 }
}

@main
@MainActor
struct NotchcastActivitiesTests {
    final class Presenter: IslandActivityPresenter {}

    static func main() async throws {
        let center = IslandActivityCenter()
        let status = center.begin(IslandActivity(kind: .status, priority: 100, title: "Status"))
        let transfer = center.begin(IslandActivity(kind: .transfer, title: "Transfer"))
        precondition(center.current?.id == transfer)
        let timer = center.begin(IslandActivity(kind: .timer, priority: 1, title: "Timer"))
        precondition(center.current?.id == timer)
        let soon = center.begin(IslandActivity(kind: .timer, priority: 1, title: "Soon",
                                             endDate: Date(timeIntervalSince1970: 1)))
        let equal = center.begin(IslandActivity(kind: .timer, priority: 1, title: "Equal",
                                              endDate: Date(timeIntervalSince1970: 1)))
        precondition(center.current?.id == soon)
        center.finish(soon)
        precondition(center.current?.id == equal)
        center.fail(equal)
        center.fail(timer)
        precondition(center.current?.id == transfer)
        center.update(transfer, title: "Updated", progress: .some(2))
        precondition(center.current?.title == "Updated" && center.current?.progress == 1)
        center.finish(transfer)
        center.finish(status)
        center.update(transfer, title: "Stale")
        precondition(center.current == nil)
        center.showMessage("Old", tone: .success, dwell: 0.01)
        center.showMessage("New", tone: .danger, dwell: 0.08)
        try await Task.sleep(for: .seconds(0.03))
        precondition(center.message?.text == "New")
        try await Task.sleep(for: .seconds(0.08))
        precondition(center.message == nil)
        center.showMessage("Replaced", tone: .neutral, dwell: 0.01)
        center.showProgress("Working")
        try await Task.sleep(for: .seconds(0.03))
        precondition(center.message?.isProgress == true)
        center.dismissMessage()
        precondition(center.message == nil)

        let shared = IslandActivityCenter.shared
        precondition(!IslandHUDRouter.shouldRoute(statusMessagesEnabled: true))
        precondition(!IslandHUDRouter.show("Fallback", tone: .success))
        let presenter = Presenter()
        shared.presenter = presenter
        precondition(IslandHUDRouter.shouldRoute(statusMessagesEnabled: true))
        precondition(!IslandHUDRouter.shouldRoute(statusMessagesEnabled: false))
        precondition(IslandHUDRouter.show("Routed", tone: .danger))
        precondition(shared.message?.text == "Routed")
        var cancelled = false
        precondition(IslandHUDRouter.showProgress("Progress", onCancel: { cancelled = true }))
        shared.message?.onCancel?()
        precondition(cancelled)
        shared.presenter = nil
        precondition(!IslandHUDRouter.dismiss())
        precondition(shared.message == nil)
        print("PASS priority, deadlines, removal, updates, dwell, replacement, routing and cancellation")
    }
}
