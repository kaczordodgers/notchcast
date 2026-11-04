import Foundation

enum TweakProfileCommands {
    nonisolated static let ai = NotchcastCommand(
        slug: "ai-features-off", name: String(localized: "AI Features Off"),
        sfSymbol: "brain", feature: .aiFeaturesOff,
        isEnabled: { NotchcastPreferences.shared.isOn(.aiFeaturesOff) },
        run: { Task { await perform(.aiFeaturesOff) } })

    nonisolated static let privacy = NotchcastCommand(
        slug: "privacy-choices", name: String(localized: "Privacy Choices"),
        sfSymbol: "hand.raised", feature: .privacyChoices,
        isEnabled: { NotchcastPreferences.shared.isOn(.privacyChoices) },
        run: { Task { await perform(.privacyChoices) } })

    @MainActor
    private static func perform(_ feature: NotchcastFeature) async {
        let core = AppCore.shared
        let message = feature == .aiFeaturesOff
            ? String(localized: "Review a profile disabling all Apple intelligence features.")
            : String(localized: "Review a profile disabling analytics, personalized ads, web results and suggestions.")
        do {
            try await TweakProfileCommandRunner.run(ai: feature == .aiFeaturesOff,
                enabled: { NotchcastPreferences.shared.isOn(feature) },
                confirm: {
                    await core.confirm(title: feature.title, message: message,
                        symbol: "gearshape", confirmTitle: String(localized: "Open…"))
                }, request: { kept, privacy in
                    _ = try await NotchcastCore.tweaks.requestProfile(keepingAI: kept, privacy: privacy)
                })
        } catch { core.showMessage(error.localizedDescription) }
    }
}
