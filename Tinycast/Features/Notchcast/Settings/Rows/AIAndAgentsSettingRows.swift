import SwiftUI

struct AIUsageGatewaySettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField(String(localized: "Magpie gateway", table: "Notchcast"), text: $preferences.aiUsageGateway)
            .textFieldStyle(.roundedBorder)
    }
}

struct BuildStatsSnapshotSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared
    @State private var state: BuildStatsLoader.State = .unconfigured

    var body: some View {
        TextField(String(localized: "Snapshot path", table: "Notchcast"), text: $preferences.buildStatsPath)
            .textFieldStyle(.roundedBorder)
        Text(verbatim: status)
            .lineLimit(1)
            .task(id: LoadRequest(path: preferences.buildStatsPath, enabled: preferences.isOn(.buildStats))) {
                guard preferences.isOn(.buildStats) else { return }
                let path = preferences.buildStatsPath
                let result = await BuildStatsLoader.load(path: path)
                guard !Task.isCancelled, preferences.buildStatsPath == path,
                      preferences.isOn(.buildStats) else { return }
                state = result
            }
    }

    private struct LoadRequest: Equatable {
        let path: String
        let enabled: Bool
    }

    private var status: String {
        switch state {
        case .unconfigured: return String(localized: "No snapshot loaded.", table: "Notchcast")
        case let .loaded(model):
            let updated = model.modificationDate.formatted(.relative(presentation: .named))
            return String(localized: "Loaded: \(model.entryCount) entries, updated \(updated)", table: "Notchcast")
        case .failed(.missing): return String(localized: "Snapshot file is missing.", table: "Notchcast")
        case .failed(.unreadable): return String(localized: "Snapshot file cannot be read.", table: "Notchcast")
        case .failed(.tooLarge): return String(localized: "Snapshot file is too large.", table: "Notchcast")
        case .failed(.invalid), .failed(.overflow): return String(localized: "Snapshot file is invalid.", table: "Notchcast")
        }
    }
}

struct AgentCLIInstallSettingRow: View {
    let module: AgentCLIModule

    var body: some View {
        Text(status)
        .onAppear { module.installer.refresh() }
        Text(module.installer.link.path)
            .textSelection(.enabled)
    }

    private var status: String {
        if module.hasFailed { return String(localized: "Unavailable") }
        switch module.installer.state {
        case .installed: return String(localized: "Installed")
        case .notInstalled: return String(localized: "Not installed")
        case .failed: return String(localized: "Unable to install the command line tool.", table: "Notchcast")
        }
    }
}

struct AgentChatToolsAccessSettingRow: View {
    @Environment(AppCore.self) private var core
    @Bindable var module: AgentChatToolsModule

    var body: some View {
        LabeledContent {
            if module.isAdded {
                Button("Remove", action: module.remove)
            } else {
                Button(String(localized: "Add Notchcast to AI chat", table: "Notchcast")) {
                    if module.add() == .binaryMissing {
                        core.showMessage(String(localized: "Install the Notchcast CLI first.", table: "Notchcast"), tone: .danger)
                    }
                }
                .disabled(!module.isRunning)
            }
        } label: {
            Text(module.isAdded
                 ? (core.mcpCoordinator.isActive ? String(localized: "Added", table: "Notchcast") : String(localized: "Disabled"))
                 : String(localized: "Not added", table: "Notchcast"))
        }
    }
}

struct VoiceAskDestinationSettingRow: View {
    @Bindable var module: VoiceAskModule

    var body: some View {
        TextField(String(localized: "Voice Ask destination", table: "Notchcast"), text: $module.destination)
            .textFieldStyle(.roundedBorder)
    }
}
