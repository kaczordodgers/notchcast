extension PlainPasteModule: NotchcastRegistrant {
    static let shared = PlainPasteModule(clipboard: AppCore.shared.clipboardManager)

    static func register() -> [NotchcastModuleController.Entry] {
        [.init(requires: [.pastePlain], module: shared)]
    }
}
