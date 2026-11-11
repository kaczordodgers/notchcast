extension NotchcastModuleController.Entry {
    /// A registrant names only its own feature; the descriptors say what else has to be on.
    var gatedOnDependencies: Self {
        Self(requires: requires.flatMap(\.enablingChain), requiresAny: requiresAny, module: module)
    }
}

private extension NotchcastFeature {
    var enablingChain: [NotchcastFeature] { [self] + dependencies.flatMap(\.enablingChain) }
}
