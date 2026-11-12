extension ClearNotificationsModule: NotchcastRegistrant {
    static let shared = ClearNotificationsModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.clearNotifications], module: shared)]
    }
}
