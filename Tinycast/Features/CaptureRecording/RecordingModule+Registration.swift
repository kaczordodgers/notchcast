extension RecordingModule: NotchcastRegistrant {
    static let shared = RecordingModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.recording], module: shared)]
    }
}
