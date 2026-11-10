extension NotchcastAgentDevice {
    static let treadmill = Self(configure: { TreadmillCoordinator.shared.configure(index: $0) })
}
