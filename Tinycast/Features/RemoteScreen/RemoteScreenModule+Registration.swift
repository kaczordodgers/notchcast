extension RemoteScreenModule: NotchcastRegistrant {
    static private(set) var shared: RemoteScreenModule?

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        guard let linkChannel else { return [] }
        let module = RemoteScreenModule(channel: linkChannel)
        shared = module
        return [.init(requires: [.machLink, .remoteScreen], module: module)]
    }
}
