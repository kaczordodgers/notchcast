import SwiftUI

struct AIUsageCacheDirectorySettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared

    var body: some View {
        TextField("AI usage cache directory", text: $preferences.aiUsageCachePath)
            .textFieldStyle(.roundedBorder)
    }
}

struct BuildStatsSnapshotSettingRow: View {
    @Bindable private var preferences = NotchcastPreferences.shared
    @State private var state: BuildStatsLoader.State = .unconfigured

    var body: some View {
        TextField("Snapshot path", text: $preferences.buildStatsPath)
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
        case .unconfigured: return String(localized: "No snapshot loaded.")
        case let .loaded(model):
            let updated = model.modificationDate.formatted(.relative(presentation: .named))
            return String(localized: "Loaded: \(model.entryCount) entries, updated \(updated)")
        case .failed(.missing): return String(localized: "Snapshot file is missing.")
        case .failed(.unreadable): return String(localized: "Snapshot file cannot be read.")
        case .failed(.tooLarge): return String(localized: "Snapshot file is too large.")
        case .failed(.invalid), .failed(.overflow): return String(localized: "Snapshot file is invalid.")
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
        case .failed: return String(localized: "Unable to install the command line tool.")
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
                Button("Add Notchcast to AI chat") {
                    if module.add() == .binaryMissing {
                        core.showMessage(String(localized: "Install the Notchcast CLI first."), tone: .danger)
                    }
                }
                .disabled(!module.isRunning)
            }
        } label: {
            Text(module.isAdded
                 ? (core.mcpCoordinator.isActive ? String(localized: "Added") : String(localized: "Disabled"))
                 : String(localized: "Not added"))
        }
    }
}

struct VoiceAskDestinationSettingRow: View {
    @Bindable var module: VoiceAskModule

    var body: some View {
        TextField("Voice Ask destination", text: $module.destination)
            .textFieldStyle(.roundedBorder)
    }
}
