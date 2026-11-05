import AppKit
import Observation

@MainActor
@Observable
final class SpotifySettingsCoordinator {
    let module: SpotifyConnectModule
    var keyText = ""
    private(set) var hasKey = false
    @ObservationIgnored private weak var core: AppCore?
    @ObservationIgnored private var action: Task<Void, Never>?
    @ObservationIgnored private var download: Task<Void, Never>?
    @ObservationIgnored private var panel: NSOpenPanel?

    init(module: SpotifyConnectModule, core: AppCore) {
        self.module = module
        self.core = core
    }

    isolated deinit {
        action?.cancel()
        download?.cancel()
        panel?.cancel(nil)
    }

    var canSave: Bool { !keyText.isEmpty }

    func refreshKey() {
        do { hasKey = try module.key.isSaved } catch { present(.keyUnavailable) }
    }

    func save() {
        do {
            try module.key.save(keyText)
            keyText = ""
            hasKey = true
            core?.showMessage(String(localized: "API Key Saved", table: "Notchcast"))
        } catch { present((error as? SoloistFailure) ?? .keyUnavailable) }
    }

    func importKey() {
        guard panel == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        self.panel = panel
        panel.begin { [weak self, weak panel] response in
            guard let self, self.panel === panel else { return }
            self.panel = nil
            guard response == .OK, let url = panel?.url else { return }
            do {
                try self.module.key.importKey(from: url)
                self.keyText = ""
                self.hasKey = true
                self.core?.showMessage(String(localized: "API Key Saved", table: "Notchcast"))
            } catch {
                self.present((error as? SoloistFailure) ?? .keyFileUnreadable, importing: true)
            }
        }
    }

    func removeKey() {
        guard action == nil else { return }
        action = Task { [weak self] in
            guard let self else { return }
            defer { action = nil }
            guard await core?.confirm(
                title: String(localized: "Remove API key?", table: "Notchcast"),
                message: String(localized: "Spotify Connect stops until you add a key again.", table: "Notchcast"),
                symbol: "key", confirmTitle: String(localized: "Remove")) == true,
                !Task.isCancelled else { return }
            do {
                try module.key.remove()
                hasKey = false
                keyText = ""
                core?.showMessage(String(localized: "API Key Removed", table: "Notchcast"))
            } catch {
                core?.showMessage(((error as? SoloistFailure) ?? .keyNotSaved).message, tone: .danger)
            }
        }
    }

    func installBuild() {
        guard download == nil else { return }
        let speaker = module.speaker
        speaker.installBuild()
        download = Task { [weak self] in
            await speaker.installing?.value
            guard !Task.isCancelled, let self else { return }
            download = nil
            guard module.speaker === speaker, module.isEnabled else { return }
            if let failure = speaker.installFailure {
                present(failure)
            } else if speaker.build != nil {
                core?.showMessage(String(localized: "Soloist Downloaded", table: "Notchcast"))
            }
        }
    }

    private func present(_ failure: SoloistFailure, importing: Bool = false) {
        guard action == nil else { return }
        action = Task { [weak self] in
            guard let self else { return }
            defer { action = nil }
            _ = await core?.reportFailure(
                title: importing
                    ? String(localized: "Couldn’t import the API key", table: "Notchcast") : String(localized: "Spotify Connect stopped", table: "Notchcast"),
                message: importing ? failure.importMessage : failure.message,
                symbol: "hifispeaker.fill", recovery: nil)
        }
    }
}
