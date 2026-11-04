import Foundation
import Observation

@MainActor
@Observable
final class SystemToolsModule: NotchcastModule {
    private(set) var items: [StartupItem] = []
    private(set) var busy = false
    private var core: AppCore?
    private let runner = SystemToolsProcessRunner()
    private var running = false
    private var refreshTask: Task<Void, Never>?
    private let notificationCleanup = NotificationCleanupObserver()
    @ObservationIgnored private lazy var store = SystemToolsStore(preferences: .shared,
                                              available: SystemToolsHelperPolicy.available,
                                              apply: SystemToolsModule.apply)

    static func apply(_ feature: NotchcastFeature, enabled: Bool) async throws {
        guard feature == .sudoTouchID || feature == .spotlightOff else { return }
        let verb = feature == .sudoTouchID
            ? (enabled ? "sudo-touchid-on" : "sudo-touchid-off")
            : (enabled ? "spotlight-off" : "spotlight-on")
        guard let command = RootContract.Command(rawValue: verb) else { return }
        _ = try await RootHelperClient().run(command)
    }

    func configure(_ core: AppCore) { self.core = core }
    func start() {
        running = true
        notificationCleanup.start()
        refreshTask = Task { await refresh() }
    }
    func stop() {
        running = false
        refreshTask?.cancel()
        refreshTask = nil
        notificationCleanup.stop()
    }

    func set(_ feature: NotchcastFeature, enabled: Bool) async {
        guard !busy, SystemToolsHelperPolicy.available(feature) else { return }
        busy = true
        defer {
            busy = false
            if running { refreshTask = Task { await refresh() } }
        }
        do {
            if feature == .sudoTouchID || feature == .spotlightOff {
                guard let core, await core.confirm(title: feature.title, message: feature.subtitle,
                                                  symbol: "gearshape", confirmTitle: feature.title) else { return }
            }
            try await store.set(feature, enabled: enabled)
            notificationCleanup.update()
        } catch { core?.showMessage(error.localizedDescription, tone: .danger) }
    }

    func refresh() async {
        guard running, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await runner.startupItems(home: NSHomeDirectory(), uid: getuid())
            guard running, !Task.isCancelled else { return }
            items = result
        } catch is CancellationError {
            return
        } catch { core?.showMessage(error.localizedDescription, tone: .danger) }
    }

    func set(_ item: StartupItem, enabled: Bool) async {
        guard running, !busy, NotchcastPreferences.shared.isOn(.startupItems), let core else { return }
        busy = true
        defer { busy = false }
        guard await core.confirm(title: item.label, message: NotchcastFeature.startupItems.subtitle,
                                 symbol: "gearshape", confirmTitle: NotchcastFeature.startupItems.title),
              running, NotchcastPreferences.shared.isOn(.startupItems) else { return }
        do {
            try await runner.setStartupItem(item, enabled: enabled, home: NSHomeDirectory(), uid: getuid())
            let result = try await runner.startupItems(home: NSHomeDirectory(), uid: getuid())
            guard running, !Task.isCancelled, NotchcastPreferences.shared.isOn(.startupItems) else { return }
            items = result
        } catch { core.showMessage(error.localizedDescription, tone: .danger) }
    }
}
