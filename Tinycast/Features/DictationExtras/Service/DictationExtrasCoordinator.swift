import AppKit
import Observation

/// Cleanup before a dictation is pasted and the history after it; Dictation calls in through hooks.
@MainActor
@Observable
final class DictationExtrasCoordinator {
    let history = DictationHistoryStore()
    /// Hooks Notchcast's island sets; unset, cleanup reports through stock's HUD as before.
    @ObservationIgnored var cleaningUp: @MainActor () -> Void = {}
    @ObservationIgnored var cleanupFailed: @MainActor () -> Bool = { false }
    @ObservationIgnored var delivered: @MainActor (_ empty: Bool) -> Void = { _ in }
    /// Nil follows `DictationCleanupModelPolicy`: the installed Claude, else Codex.
    private(set) var cleanupModel: AIModelSelection?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var core: AppCore?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cleanupModel = defaults.data(forKey: AppSettingsKey.dictationCleanupModel.rawValue)
            .flatMap { try? JSONDecoder().decode(AIModelSelection.self, from: $0) }
    }

    func start(core: AppCore) {
        self.core = core
        core.dictationCoordinator.cleanUp = { [weak self] transcript, cleansUp, hasField, liveTextEmpty in
            await self?.clean(transcript, cleansUp: cleansUp, hasField: hasField, liveTextEmpty: liveTextEmpty)
        }
        core.dictationCoordinator.didDictate = { [weak self] raw, cleaned, target in
            self?.record(raw: raw, cleaned: cleaned, target: target)
            self?.delivered(raw.isEmpty)
        }
        observe { [weak self] in self?.applySettings() }
    }

    /// Whether the installed commands must be probed even with AI and Quick Actions off.
    var usesInstalledAI: Bool {
        guard let settings = core?.settings else { return false }
        return settings.dictationEnabled && settings.dictationCleansUp
    }

    func selectCleanupModel(_ selection: AIModelSelection?) {
        cleanupModel = selection
        if let selection, let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: AppSettingsKey.dictationCleanupModel.rawValue)
        } else {
            defaults.removeObject(forKey: AppSettingsKey.dictationCleanupModel.rawValue)
        }
    }

    /// The model an unset choice resolves to right now, for Settings to name.
    var automaticModel: AIModelOption? {
        guard let core else { return nil }
        let options = AIModelOption.availableGroups(
            settings: core.aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI
        ).flatMap(\.options)
        return DictationCleanupModelPolicy.automatic(
            from: options,
            source: {
                switch $0.selection.source {
                case .claude: .claude
                case .codex: .codex
                default: .other
                }
            },
            id: \.selection.model)
    }

    // MARK: - Cleanup

    /// Nil pastes the raw transcript; a cleanup the reader wanted and did not get says so.
    private func clean(
        _ transcript: String, cleansUp: Bool, hasField: Bool, liveTextEmpty: Bool
    ) async -> String? {
        guard let core,
            DictationCleanupPolicy.sends(
                switchOn: core.settings.dictationCleansUp, cleansUp: cleansUp, hasField: hasField,
                liveTextEmpty: liveTextEmpty)
        else { return nil }
        cleaningUp()
        let outcome = await DictationCleanupRunner.run(
            transcript, generate: generator(for: transcript, core: core),
            usesDefaultPrompt: DictationCleanupPrompt.instructions(custom: core.settings.dictationCleanupPrompt)
                == DictationCleanupPrompt.standard,
            probingInstalledModels: isProbingAutomaticModels(core: core),
            deadline: { try await Task.sleep(for: DictationCleanupRunner.timeout) })
        guard !Task.isCancelled else { return nil }
        switch outcome {
        case .cleaned(let text):
            return text
        case .skipped:
            return nil
        case .failed(.noModel):
            core.dictationCoordinator.showMessage(
                String(localized: "Cleanup has no model, so the raw text was pasted", table: "Notchcast"),
                .danger)
        case .failed where cleanupFailed():
            break
        case .failed(.timeout):
            core.showMessage(
                String(localized: "Cleanup took too long, so the raw text was pasted", table: "Notchcast"),
                tone: .danger)
        case .failed:
            core.showMessage(
                String(localized: "Cleanup was skipped, so the raw text was pasted", table: "Notchcast"),
                tone: .danger)
        }
        return nil
    }

    private func isProbingAutomaticModels(core: AppCore) -> Bool {
        let enabled = core.aiSettings.enabledInstalledProviders
        return (enabled.contains(.claude) && core.installedAI.status(for: .claude).phase == .checking)
            || (enabled.contains(.codex) && core.chatGPTSubscription.phase == .starting)
    }

    /// Nil when nothing can clean up; a route that cannot be built fails in the race, loudly.
    private func generator(
        for transcript: String, core: AppCore
    ) -> (@Sendable () async throws -> String)? {
        let selection =
            cleanupModel
            ?? automaticModel.map {
                AIModelOption.withDefaultEffort(
                    $0.selection, settings: core.aiSettings, subscription: core.chatGPTSubscription,
                    installedAI: core.installedAI)
            }
        guard let selection else { return nil }
        let provider: any AIProvider
        do {
            provider = try AIProviderFactory.make(
                selection: selection, settings: core.aiSettings, subscription: core.chatGPTSubscription,
                installedAI: core.installedAI, guardrails: .permissiveContentTransformations)
        } catch {
            let message = error.localizedDescription
            return { throw AIProviderError.unavailable(message) }
        }
        let request = AIRequest(
            instructions: DictationCleanupPrompt.instructions(custom: core.settings.dictationCleanupPrompt),
            messages: [AIMessage(role: .user, text: DictationCleanupPrompt.message(for: transcript))],
            maxOutputTokens: provider is AppleIntelligenceProvider
                ? max(transcript.count / 3, 64) * 2 : AIRequest.defaultMaxOutputTokens)
        return {
            var text = ""
            for try await event in provider.stream(request) {
                if case .text(let delta) = event { text += delta }
            }
            try Task.checkCancellation()
            return text
        }
    }

    // MARK: - History

    private func record(raw: String, cleaned: String?, target: InjectionTarget?) {
        guard let core, core.settings.dictationKeepsHistory else { return }
        var app: String?
        if case .external(let running)? = target { app = running.localizedName }
        history.record(raw: raw, cleaned: cleaned, app: app, at: Date())
    }

    func paste(_ text: String) {
        guard let core else { return }
        let target = core.paletteCoordinator.targetApp
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteString(text, previousApp: target)
    }

    func copy(_ text: String) {
        core?.paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(text)
    }

    func clearHistory() async {
        guard let core, !history.entries.isEmpty,
            await core.confirm(
                title: String(localized: "Clear dictation history?", table: "Notchcast"),
                message: String(
                    localized: "Every saved dictation goes. This can't be undone.", table: "Notchcast"),
                symbol: CommandID.dictationHistory.sfSymbol,
                confirmTitle: String(localized: "Clear History"))
        else { return }
        history.clear()
    }

    // MARK: - Settings

    /// History off deletes it; the launcher row and the installed commands follow the switches.
    private func applySettings() {
        guard let core else { return }
        let settings = core.settings
        if !settings.dictationKeepsHistory { history.clear() }
        core.appIndex.setCommandsVisible(
            [.dictationHistory], settings.dictationEnabled && settings.dictationKeepsHistory)
        core.applyInstalledAILifecycle()
    }

    /// Runs `apply` now and again after each change to the switches it reads.
    private func observe(_ apply: @escaping @Sendable @MainActor () -> Void) {
        guard let settings = core?.settings else { return }
        withObservationTracking {
            _ = settings.dictationEnabled
            _ = settings.dictationCleansUp
            _ = settings.dictationKeepsHistory
            _ = core?.aiSettings.enabledInstalledProviders
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe(apply) }
        }
        apply()
    }
}
