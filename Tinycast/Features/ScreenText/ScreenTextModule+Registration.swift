extension ScreenTextModule: NotchcastRegistrant {
    static let shared = ScreenTextModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.screenText], module: shared)]
    }
}
