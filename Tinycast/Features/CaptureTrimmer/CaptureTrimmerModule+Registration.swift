extension CaptureTrimmerModule: NotchcastRegistrant {
    static let shared = CaptureTrimmerModule.live()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.captureTrimmer], module: shared)]
    }
}
