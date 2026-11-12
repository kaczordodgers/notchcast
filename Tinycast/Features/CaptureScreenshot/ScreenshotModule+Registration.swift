extension ScreenshotModule: NotchcastRegistrant {
    static let shared = ScreenshotModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.screenshot], module: shared)]
    }
}
