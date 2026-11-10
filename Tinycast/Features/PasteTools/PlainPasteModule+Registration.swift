extension PlainPasteModule: NotchcastRegistrant {
    static private(set) var shared: PlainPasteModule?

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        let module = PlainPasteModule(clipboard: core.clipboardManager)
        shared = module
        return [.init(requires: [.pastePlain], module: module)]
    }
}
