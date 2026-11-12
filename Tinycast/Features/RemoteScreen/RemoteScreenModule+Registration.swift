extension RemoteScreenModule: NotchcastRegistrant {
    static private(set) var shared: RemoteScreenModule?

    static func register() -> [NotchcastModuleController.Entry] {
        guard let linkChannel else { return [] }
        let module = RemoteScreenModule(channel: linkChannel)
        shared = module
        return [.init(requires: [.remoteScreen], module: module)]
    }
}
