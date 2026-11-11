extension ClearNotificationsModule: NotchcastRegistrant {
    static let shared = ClearNotificationsModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.clearNotifications], module: shared)]
    }
}
