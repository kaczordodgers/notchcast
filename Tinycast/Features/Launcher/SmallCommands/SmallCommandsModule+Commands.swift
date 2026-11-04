import AppKit

extension SmallCommandsModule {
    enum Action {
        case password
        case shorten
        case noise
        case airDrop
    }

    nonisolated static let passwordCommand = NotchcastCommand(
        slug: "generate-password", name: String(localized: "Generate Password"), sfSymbol: "key", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { NotchcastCore.smallCommands.runFromLauncher(.password) })
    nonisolated static let shortenCommand = NotchcastCommand(
        slug: "shorten-link", name: String(localized: "Shorten Link"), sfSymbol: "link", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { NotchcastCore.smallCommands.runFromLauncher(.shorten) })
    nonisolated static let noiseCommand = NotchcastCommand(
        slug: "switch-noise-control", name: String(localized: "Switch Noise Control"),
        sfSymbol: "airpodspro", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { NotchcastCore.smallCommands.runFromLauncher(.noise) })
    nonisolated static let airDropCommand = NotchcastCommand(
        slug: "airdrop-selection", name: String(localized: "AirDrop Selected Files"),
        sfSymbol: "airplayaudio", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { NotchcastCore.smallCommands.runFromLauncher(.airDrop) })

    func runFromLauncher(_ action: Action,
                         execute: ((Action) async throws -> String?)? = nil,
                         copy: @escaping (String) -> Bool = {
                             NSPasteboard.general.clearContents()
                             return NSPasteboard.general.setString($0, forType: .string)
                         },
                         report: @escaping (String) -> Void = {
                             AppCore.shared.showMessage($0, tone: .neutral)
                         }) {
        guard isRunning else { return }
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await (execute ?? perform)(action)
                guard !Task.isCancelled, isRunning else { return }
                if let text {
                    report(copy(text) ? String(localized: "Copied") : String(localized: "Could not copy to clipboard."))
                } else {
                    report(String(localized: "Done"))
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, isRunning else { return }
                report(String(localized: "Unavailable"))
            }
        }
    }

    private func perform(_ action: Action) async throws -> String? {
        switch action {
        case .password:
            return try randomPassword()
        case .shorten:
            guard let shortener, let address = ShortenLinkService.pick(argument: "", frontAddress: nil,
                clipboard: NSPasteboard.general.string(forType: .string)) else { throw Failure.disabled }
            return try await shortener.shorten(address)
        case .noise:
            guard let controlCenter = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.controlcenter").first else { throw Failure.disabled }
            let outcome = try await noiseControl(processID: controlCenter.processIdentifier).switchMode()
            guard case .switched = outcome else { throw Failure.disabled }
            return nil
        case .airDrop:
            guard let airDrop else { throw Failure.disabled }
            let outcome = try await airDrop.shareSelection()
            guard case .sent = outcome else { throw Failure.disabled }
            return nil
        }
    }
}
