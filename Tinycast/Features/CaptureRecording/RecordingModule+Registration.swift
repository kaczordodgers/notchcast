extension RecordingModule: NotchcastRegistrant {
    static let shared = RecordingModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.recording], module: shared)]
    }
}
