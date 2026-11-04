import SwiftUI

struct MacLinkStatusSettingRow: View {
    let link: AIUsageLinkModule

    var body: some View {
        LabeledContent("Status", value: link.isPaired
            ? String(localized: "Paired") : String(localized: "Not connected"))
            .settingsEnabled(link.isRunning)
    }
}

struct MacLinkPairingSettingRow: View {
    let link: AIUsageLinkModule
    @State private var code = ""
    @State private var failed = false

    var body: some View {
        Group {
            RevealableSecureField(title: String(localized: "Pairing code"), text: $code)
            Button(link.isPaired ? String(localized: "Unpair") : String(localized: "Pair")) {
                do {
                    if link.isPaired {
                        try link.unpair()
                        code = ""
                    } else {
                        code = try link.pair(code: code)
                    }
                    failed = false
                } catch { failed = true }
            }
            if failed || link.failed { Text("Pairing failed.").foregroundStyle(.secondary) }
            Text("Pair with an empty code to create one, then enter it on the other Mac.")
        }
        .settingsEnabled(link.isRunning)
    }
}

struct RemoteMacAddressSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField("Remote Mac address", text: $preferences.remoteMacAddress)
            .textFieldStyle(.roundedBorder)
            .settingsAnchor(.notchcastRemoteMac)
    }
}

struct RemoteTerminalDirectorySettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField("Remote terminal directory", text: $preferences.remoteTerminalDirectory)
            .textFieldStyle(.roundedBorder)
    }
}

struct RemoteUpdateScriptSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField("Remote update script path", text: $preferences.remoteUpdatePath)
            .textFieldStyle(.roundedBorder)
    }
}
