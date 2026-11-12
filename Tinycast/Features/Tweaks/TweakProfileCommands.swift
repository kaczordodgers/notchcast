import Foundation

enum TweakProfileCommands {
    nonisolated static let ai = NotchcastCommand(
        slug: "ai-features-off", name: String(localized: "AI Features Off", table: "Notchcast"),
        sfSymbol: "brain", feature: .aiFeaturesOff,
        isEnabled: { NotchcastPreferences.shared.isOn(.aiFeaturesOff) },
        run: { Task { await perform(.aiFeaturesOff) } })

    nonisolated static let privacy = NotchcastCommand(
        slug: "privacy-choices", name: String(localized: "Privacy Choices", table: "Notchcast"),
        sfSymbol: "hand.raised", feature: .privacyChoices,
        isEnabled: { NotchcastPreferences.shared.isOn(.privacyChoices) },
        run: { Task { await perform(.privacyChoices) } })

    @MainActor
    private static func perform(_ feature: NotchcastFeature) async {
        let host = NotchcastHost.current
        let message = feature == .aiFeaturesOff
            ? String(localized: "Review a profile disabling all Apple intelligence features.", table: "Notchcast")
            : String(localized: "Review a profile disabling analytics, personalized ads, web results and suggestions.", table: "Notchcast")
        do {
            try await TweakProfileCommandRunner.run(ai: feature == .aiFeaturesOff,
                enabled: { NotchcastPreferences.shared.isOn(feature) },
                confirm: {
                    await host.confirm(feature.title, message, "gearshape", String(localized: "Open…"))
                }, request: { kept, privacy in
                    _ = try await TweaksModule.shared.requestProfile(keepingAI: kept, privacy: privacy)
                })
        } catch { host.showMessage(error.localizedDescription, .success) }
    }
}
