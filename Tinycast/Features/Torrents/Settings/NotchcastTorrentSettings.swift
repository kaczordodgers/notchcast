import SwiftUI

struct NotchcastTorrentSettings: View {
    let module: TorrentModule

    var body: some View {
        Section {
            Toggle(isOn: binding(.torrents)) {
                SettingsRowTitle(.notchcastTorrents, "Torrents")
                Text(NotchcastFeature.torrents.subtitle)
            }
            Toggle(isOn: binding(.torrentsUseIPhone)) {
                SettingsRowTitle(.notchcastTorrents, "Use a plugged-in iPhone for big downloads")
                Text(NotchcastFeature.torrentsUseIPhone.subtitle)
            }
            .settingsEnabled(module.preferences.isOn(.torrents))
            Toggle(isOn: binding(.torrentsKeepSharing)) {
                SettingsRowTitle(.notchcastTorrents, "Keep sharing until ratio 1.0")
                Text(NotchcastFeature.torrentsKeepSharing.subtitle)
            }
            .settingsEnabled(module.preferences.isOn(.torrents))
            LabeledContent {
                if let url = module.toolURL {
                    Text(verbatim: url.path).textSelection(.enabled)
                } else if !module.toolChecked {
                    Text("Checking…")
                } else {
                    Text("aria2c not found")
                }
            } label: {
                SettingsRowTitle(.notchcastTorrents, "aria2c")
                Text("Install aria2c with Homebrew: brew install aria2")
            }
            ForEach(module.manager.jobs) { job in
                TorrentSettingsJobRow(job: job, module: module)
            }
        } header: {
            SettingsSectionHeader(.notchcastTorrents)
        }
        .task { await module.refreshTool() }
    }

    private func binding(_ feature: NotchcastFeature) -> Binding<Bool> {
        Binding(get: { module.preferences.isOn(feature) }, set: { module.preferences.set(feature, $0) })
    }
}
