import Foundation

@MainActor
final class AppleAppsUndoModule: NotchcastModule {
    private(set) var running = false
    let store: AppleAppsUndoStore?
    var onFailure: (Error) -> Void = { _ in }
    private let loadFailure: Error?

    init(defaults: UserDefaults,
         readDock: @escaping () throws -> Data = AppleAppsService().readDock,
         writeDock: @escaping (Data) throws -> Void = AppleAppsService().writeDock,
         restartDock: @escaping () throws -> Void = {
             _ = try SystemToolsProcessRunner().run("/usr/bin/killall", arguments: ["Dock"])
         }) {
        do {
            let receipt = try defaults.data(forKey: "appleAppsUndoReceipt").map {
                try JSONDecoder().decode(AppleAppsUndoStore.Receipt.self, from: $0)
            } ?? .init()
            store = AppleAppsUndoStore(receipt: receipt, readDock: readDock,
                writeDock: {
                    try writeDock($0)
                    try restartDock()
                }, readMusic: { throw CocoaError(.featureUnsupported) },
                disableMusic: { throw CocoaError(.featureUnsupported) },
                restoreMusic: { _ in throw CocoaError(.featureUnsupported) }, save: {
                    defaults.set(try JSONEncoder().encode($0), forKey: "appleAppsUndoReceipt")
                })
            loadFailure = nil
        } catch {
            store = nil
            loadFailure = error
        }
    }

    func start() {
        running = true
        if let loadFailure { onFailure(loadFailure) }
    }

    func setDock(_ enabled: Bool) {
        guard running else { return }
        do { try store?.setDock(enabled) } catch { onFailure(error) }
    }

    func stop() {
        running = false
        do { try store?.stop() } catch { onFailure(error) }
    }
}
