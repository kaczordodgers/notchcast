extension ColorPickerModule: NotchcastRegistrant {
    static let shared = ColorPickerModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.colorPicker], module: shared)]
    }
}
