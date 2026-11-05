import SwiftUI

struct MacLinkStatusSettingRow: View {
    let link: AIUsageLinkModule

    var body: some View {
        LabeledContent("Status", value: link.isPaired
            ? String(localized: "Paired", table: "Notchcast") : String(localized: "Not connected", table: "Notchcast"))
            .settingsEnabled(link.isRunning)
    }
}

struct MacLinkPairingSettingRow: View {
    let link: AIUsageLinkModule
    @State private var code = ""
    @State private var failed = false

    var body: some View {
        Group {
            RevealableSecureField(title: String(localized: "Pairing code", table: "Notchcast"), text: $code)
            Button(link.isPaired ? String(localized: "Unpair", table: "Notchcast") : String(localized: "Pair", table: "Notchcast")) {
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
            if failed || link.failed { Text("Pairing failed.", tableName: "Notchcast").foregroundStyle(.secondary) }
            Text("Pair with an empty code to create one, then enter it on the other Mac.", tableName: "Notchcast")
        }
        .settingsEnabled(link.isRunning)
    }
}

struct RemoteMacAddressSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField(String(localized: "Remote Mac address", table: "Notchcast"), text: $preferences.remoteMacAddress)
            .textFieldStyle(.roundedBorder)
            .settingsAnchor(.notchcastRemoteMac)
    }
}

struct RemoteTerminalDirectorySettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField(String(localized: "Remote terminal directory", table: "Notchcast"), text: $preferences.remoteTerminalDirectory)
            .textFieldStyle(.roundedBorder)
    }
}

struct RemoteUpdateScriptSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField(String(localized: "Remote update script path", table: "Notchcast"), text: $preferences.remoteUpdatePath)
            .textFieldStyle(.roundedBorder)
    }
}
