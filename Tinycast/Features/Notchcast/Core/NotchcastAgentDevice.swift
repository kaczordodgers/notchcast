/// A feature's agent device actions, supplied from `<Name>AgentDevice.swift` in its own folder.
@MainActor
struct NotchcastAgentDevice {
    let configure: (AgentActionIndex) -> Void

    /// One feature per line, so branches that add features merge without touching each other's entry.
    static let all: [Self] = [
        .katana,
        .treadmill,
    ]
}
