extension ScrollingCaptureModule: NotchcastRegistrant {
    static let shared = ScrollingCaptureModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.scrollingCapture], module: shared)]
    }
}
