extension ScrollingCaptureModule: NotchcastRegistrant {
    static let shared = ScrollingCaptureModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.scrollingCapture], module: shared)]
    }
}
