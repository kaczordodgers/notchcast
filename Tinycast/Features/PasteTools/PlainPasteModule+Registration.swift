extension PlainPasteModule: NotchcastRegistrant {
    static let shared = PlainPasteModule(clipboard: AppCore.shared.clipboardManager)

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.pastePlain], module: shared)]
    }
}
