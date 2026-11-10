extension ScreenshotModule: NotchcastRegistrant {
    static let shared = ScreenshotModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.screenshot], module: shared)]
    }
}
