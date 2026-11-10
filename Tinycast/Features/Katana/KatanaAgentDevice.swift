extension NotchcastAgentDevice {
    static let katana = Self(configure: { KatanaModule.shared.configure(index: $0) })
}
