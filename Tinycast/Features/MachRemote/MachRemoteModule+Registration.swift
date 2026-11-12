extension MachRemoteModule: NotchcastRegistrant {
    static let shared = MachRemoteModule()

    static func register() -> [NotchcastModuleController.Entry] {
        [
            .init(requires: [.machRemote], module: shared),
            .init(requires: [.sendFiles], module: SendFilesModule.shared),
            .init(requires: [.updateRemote], module: UpdateRemoteModule.shared),
        ]
    }
}

extension SendFilesModule {
    static let shared = SendFilesModule(preferences: .shared, runner: MachSSHProcessRunner.run,
        post: { NotchcastHost.current.remoteResult($0) }, changed: { NotchcastHost.current.refreshNotchcastCommands() })
}

extension UpdateRemoteModule {
    static let shared = UpdateRemoteModule(preferences: .shared, runner: MachSSHProcessRunner.run,
        post: { NotchcastHost.current.remoteResult($0) }, changed: { NotchcastHost.current.refreshNotchcastCommands() })
}
