import AppKit

extension SmallCommandsModule {
    enum Action {
        case password
        case shorten
        case noise
        case airDrop
    }

    nonisolated static let passwordCommand = NotchcastCommand(
        slug: "generate-password", name: String(localized: "Generate Password", table: "Notchcast"), sfSymbol: "key", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { SmallCommandsModule.shared.runFromLauncher(.password) })
    nonisolated static let shortenCommand = NotchcastCommand(
        slug: "shorten-link", name: String(localized: "Shorten Link", table: "Notchcast"), sfSymbol: "link", feature: .smallCommands,
        argumentCount: 1, isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { SmallCommandsModule.shared.runFromLauncher(.shorten) })
    nonisolated static let noiseCommand = NotchcastCommand(
        slug: "switch-noise-control", name: String(localized: "Switch Noise Control", table: "Notchcast"),
        sfSymbol: "airpodspro", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { SmallCommandsModule.shared.runFromLauncher(.noise) })
    nonisolated static let airDropCommand = NotchcastCommand(
        slug: "airdrop-selection", name: String(localized: "AirDrop Selected Files", table: "Notchcast"),
        sfSymbol: "airplayaudio", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { SmallCommandsModule.shared.runFromLauncher(.airDrop) })

    func runFromLauncher(_ action: Action, argument: String = "",
                         execute: ((Action) async throws -> String?)? = nil,
                         copy: @escaping (String) -> Bool = {
                             NSPasteboard.general.clearContents()
                             return NSPasteboard.general.setString($0, forType: .string)
                         },
                         report: @escaping (String) -> Void = {
                             NotchcastHost.current.showMessage($0, .neutral)
                         }) {
        guard isRunning else { return }
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await (execute ?? { try await self.perform($0, argument: argument) })(action)
                guard !Task.isCancelled, isRunning else { return }
                if let text {
                    report(copy(text) ? String(localized: "Copied") : String(localized: "Could not copy to clipboard.", table: "Notchcast"))
                } else {
                    report(String(localized: "Done"))
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, isRunning else { return }
                report((error as? any LocalizedError)?.errorDescription ?? String(localized: "Unavailable"))
            }
        }
    }

    func perform(_ action: Action, argument: String = "",
                 frontAddress: () async -> String? = SmallCommandsModule.frontAddress,
                 clipboard: () -> String? = { NSPasteboard.general.string(forType: .string) },
                 service: ShortenLinkService? = nil) async throws -> String? {
        switch action {
        case .password:
            return try randomPassword()
        case .shorten:
            let front = await frontAddress()
            try Task.checkCancellation()
            guard let shortener = service ?? shortener else { throw SmallCommandsFailure.disabled }
            guard let address = ShortenLinkService.pick(argument: argument, frontAddress: front,
                clipboard: clipboard()) else { throw SmallCommandsFailure.noLink }
            return try await shortener.shorten(address)
        case .noise:
            guard let controlCenter = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.controlcenter").first else {
                throw SmallCommandsFailure.controlCenterNotRunning
            }
            if let failure = Self.failure(try await noiseControl(processID: controlCenter.processIdentifier).switchMode()) {
                throw failure
            }
            return nil
        case .airDrop:
            guard let airDrop else { throw SmallCommandsFailure.disabled }
            if let failure = Self.failure(try await airDrop.shareSelection()) { throw failure }
            return nil
        }
    }

    static func failure(_ outcome: NoiseControlService.Outcome) -> SmallCommandsFailure? {
        switch outcome {
        case .switched: nil
        case .noAirPods: .noAirPods
        case .unchanged: .noiseControlUnchanged
        }
    }

    static func failure(_ outcome: AirDropService.Outcome) -> SmallCommandsFailure? {
        switch outcome {
        case .sent: nil
        case .cancelled: .airDropCancelled
        case .noSelection: .nothingSelected
        case .unavailable: .airDropUnavailable
        }
    }

    static func frontAddress() async -> String? {
        guard let app = NSWorkspace.shared.menuBarOwningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        if let addresses = try? await NotchcastHost.current.browserAddresses(app.processIdentifier, app.bundleIdentifier),
           let address = ShortenLinkService.pick(argument: "", frontAddress: addresses.first, clipboard: nil) {
            return address
        }
        guard !Task.isCancelled else { return nil }
        return AccessibilityText.selection(in: app)
    }
}
