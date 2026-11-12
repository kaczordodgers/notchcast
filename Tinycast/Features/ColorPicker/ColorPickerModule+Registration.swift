extension ColorPickerModule: NotchcastRegistrant {
    static let shared = ColorPickerModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.colorPicker], module: shared)]
    }
}
