import Foundation

/// Runs at every launch whatever the switch says, so a switch-off whose restore never ran still gets one.
@MainActor
final class IPhoneBackupRecovery: NotchcastModule {
    private let context: NotchcastContext
    private let store: IPhoneBackupStore

    init(context: NotchcastContext, system: IPhoneBackupSystem) {
        self.context = context
        store = IPhoneBackupStore(context: context, system: system)
    }

    func start() {
        if context.isEnabled(IPhoneBackupAddon.switchID) {
            store.dropUnanswered()
        } else {
            store.restore(bounceOnFailure: false)
        }
    }

    func stop() {}
}
