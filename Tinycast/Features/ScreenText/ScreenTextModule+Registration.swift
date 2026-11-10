extension ScreenTextModule: NotchcastRegistrant {
    static let shared = ScreenTextModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.screenText], module: shared)]
    }
}
