import Foundation

extension RemoteMacFansModule {
    nonisolated static let autoCommand = command("remote-mac-fans-auto", name: String(localized: "Remote Mac Fans Auto"), mode: .auto)
    nonisolated static let mediumCommand = command("remote-mac-fans-60", name: String(localized: "Remote Mac Fans 60%"), mode: .medium)
    nonisolated static let maxCommand = command("remote-mac-fans-max", name: String(localized: "Remote Mac Fans Max"), mode: .max)

    nonisolated private static func command(_ slug: String, name: String, mode: FanControl.Mode) -> NotchcastCommand {
        NotchcastCommand(slug: slug, name: name, sfSymbol: "fan",
            isEnabled: { NotchcastPreferences.shared.isOn(.machRemote) && NotchcastPreferences.shared.isOn(.remoteMacFans) },
            run: { NotchcastCore.remoteMacFans.set(mode) })
    }
}
