import AppKit
import Observation
import OSLog

@MainActor @Observable
final class AppearanceCoordinator: NotchcastModule {
    let store: AppearanceStore
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private let preferences: NotchcastPreferences
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var operationID = UUID()
    @ObservationIgnored private weak var previewWindow: NSWindow?
    @ObservationIgnored private var originalAppearance: NSAppearance?
    @ObservationIgnored private var previewOwner: UUID?
    @ObservationIgnored private var reportedReset = false

    init(
        core: AppCore, store: AppearanceStore? = nil,
        preferences: NotchcastPreferences = .shared
    ) {
        self.core = core
        self.preferences = preferences
        self.store = store ?? AppearanceStore(enabled: preferences.isOn(.appearance))
    }

    var isEnabled: Bool { preferences.isOn(.appearance) }

    func start() {
        store.setEnabled(true)
        core.appIndex.refreshNotchcastCommands()
        if !reportedReset, !store.invalidPreferenceKeys.isEmpty {
            reportedReset = true
            core.showMessage(String(localized: "Theme Reset", table: "Notchcast"), tone: .danger)
        }
    }

    func stop() {
        importTask?.cancel()
        importTask = nil
        operationID = UUID()
        endPreview()
        store.setEnabled(false)
        core.appIndex.refreshNotchcastCommands()
        if core.palette.mode == .theme { core.paletteCoordinator.popToRootNow() }
    }

    func showThemes() {
        guard isEnabled else { return }
        core.paletteCoordinator.togglePalette(mode: .theme)
    }

    func setSurface(_ style: AppearanceSurfaceStyle) {
        guard isEnabled else { return }
        store.surfaceStyle = style
    }

    func setOpacity(_ opacity: Double) {
        guard isEnabled else { return }
        store.backgroundOpacity = opacity
    }

    func apply(_ target: RaycastThemeLink.Target) {
        guard isEnabled else { return }
        endPreview()
        do {
            try store.select(target.theme, for: target.appearance)
            core.showMessage(String(localized: "Theme Applied", table: "Notchcast"))
        } catch {
            reportFailure()
        }
    }

    func remove(_ theme: RaycastTheme) {
        guard isEnabled else { return }
        endPreview()
        do {
            try store.remove(theme)
        } catch {
            reportFailure()
        }
    }

    func preview(_ target: RaycastThemeLink.Target?, owner: UUID, window: NSWindow?) {
        guard isEnabled else { return }
        guard let target, let window else { return endPreview(owner: owner) }
        if previewOwner != owner || previewWindow !== window {
            endPreview()
            previewOwner = owner
            previewWindow = window
            originalAppearance = window.appearance
        }
        window.appearance = NSAppearance(named: target.appearance == .dark ? .darkAqua : .aqua)
        store.preview(target)
    }

    func previewInPalette(_ target: RaycastThemeLink.Target?, owner: UUID) {
        preview(target, owner: owner, window: core.paletteCoordinator.anchorView?.window)
    }

    func endPreview(owner: UUID? = nil) {
        guard owner == nil || owner == previewOwner else { return }
        previewWindow?.appearance = originalAppearance
        previewWindow = nil
        originalAppearance = nil
        previewOwner = nil
        store.preview(nil)
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard ["raycast", AppURLScheme.current].contains(url.scheme?.lowercased() ?? ""),
            url.host(percentEncoded: false)?.lowercased() == "theme"
        else { return false }
        guard isEnabled else {
            Logger(subsystem: NotchcastIdentity.current.loggerSubsystem(fallback: NotchcastIdentity.releaseBundleIdentifier), category: "Appearance")
                .notice("Theme link ignored because Appearance is disabled.")
            return true
        }
        importLink(url.absoluteString)
        return true
    }

    func importLink(_ text: String) {
        guard isEnabled, importTask == nil else { return }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            let request = store.requestImport(url: url, applicationScheme: AppURLScheme.current)
        else { return reportFailure() }
        endPreview()
        let operation = UUID()
        operationID = operation
        importTask = Task { [weak self] in
            guard let self else { return }
            defer { if operationID == operation { importTask = nil } }
            let dialog = ThemeImportDialog.request(for: request)
            let answer = await core.choose(
                title: dialog.title, message: dialog.message, symbol: dialog.symbol,
                options: dialog.actions, defaultIndex: dialog.defaultIndex)
            guard !Task.isCancelled, operationID == operation, isEnabled,
                store.pendingImport?.id == request.id else { return }
            let choice: AppearanceThemeImport.Choice = answer == 0 ? .useTheme : answer == 1 ? .justAdd : .cancel
            do {
                try store.resolveImport(id: request.id, choice: choice)
                switch choice {
                case .useTheme: core.showMessage(String(localized: "Theme Applied", table: "Notchcast"))
                case .justAdd: core.showMessage(String(localized: "Theme Added", table: "Notchcast"))
                case .cancel: break
                }
            } catch {
                try? store.resolveImport(id: request.id, choice: .cancel)
                await showFailure()
            }
        }
    }

    private func reportFailure() {
        guard importTask == nil else { return }
        let operation = UUID()
        operationID = operation
        importTask = Task { [weak self] in
            guard let self else { return }
            defer { if operationID == operation { importTask = nil } }
            await showFailure()
        }
    }

    private func showFailure() async {
        _ = await core.reportFailure(
            title: String(localized: "Couldn't add the theme", table: "Notchcast"),
            message: String(localized: "The link doesn't contain a valid theme.", table: "Notchcast"),
            symbol: "paintpalette", recovery: nil)
    }
}
