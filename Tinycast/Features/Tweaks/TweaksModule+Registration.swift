extension TweaksModule: NotchcastRegistrant {
    static let shared = TweaksModule()
    static let typing = TweaksModule(key: "typingTweaksPlans")
    static let finder = TweaksModule(key: "finderTweaksPlans")
    static let dock = TweaksModule(key: "dockTweaksPlans")
    static let appleApps = TweaksModule(key: "appleAppsTweaksPlans")
    static let iPhoneBackup = TweaksModule(key: "iPhoneBackupTweaksPlans")

    static func register() -> [NotchcastModuleController.Entry] {
        for module in [shared, typing, finder, dock, appleApps, iPhoneBackup] {
            module.configure()
        }
        return [
            .init(requires: [], requiresAny: [.aiFeaturesOff, .spotlightOff, .privacyChoices], module: shared),
            .init(requires: [.typingTweaks], module: typing),
            .init(requires: [.finderTweaks], module: finder),
            .init(requires: [.dockTweaks], module: dock),
            .init(requires: [.appleAppsTweaks], module: appleApps),
            .init(requires: [.iPhoneBackupTweaks], module: iPhoneBackup),
        ]
    }
}
