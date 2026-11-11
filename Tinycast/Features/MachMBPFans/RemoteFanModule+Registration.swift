extension RemoteFanModule: NotchcastRegistrant {
    static private(set) var shared: RemoteFanModule?

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        guard let linkChannel else { return [] }
        let module = RemoteFanModule(transport: MachLinkFanTransport(channel: linkChannel))
        shared = module
        return [.init(requires: [.machMBPFans], module: module)]
    }
}
