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
        run: { NotchcastCore.smallCommands.runFromLauncher(.password) })
    nonisolated static let shortenCommand = NotchcastCommand(
        slug: "shorten-link", name: String(localized: "Shorten Link", table: "Notchcast"), sfSymbol: "link", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { NotchcastCore.smallCommands.runFromLauncher(.shorten) })
    nonisolated static let noiseCommand = NotchcastCommand(
        slug: "switch-noise-control", name: String(localized: "Switch Noise Control", table: "Notchcast"),
        sfSymbol: "airpodspro", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { NotchcastCore.smallCommands.runFromLauncher(.noise) })
    nonisolated static let airDropCommand = NotchcastCommand(
        slug: "airdrop-selection", name: String(localized: "AirDrop Selected Files", table: "Notchcast"),
        sfSymbol: "airplayaudio", feature: .smallCommands,
        isEnabled: { NotchcastPreferences.shared.isOn(.smallCommands) },
        run: { NotchcastCore.smallCommands.runFromLauncher(.airDrop) })

    func runFromLauncher(_ action: Action, argument: String = "",
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
                report(String(localized: "Unavailable"))
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
            guard let shortener = service ?? shortener,
                  let address = ShortenLinkService.pick(argument: argument, frontAddress: front,
                    clipboard: clipboard()) else { throw Failure.disabled }
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

    static func frontAddress() async -> String? {
        guard let app = NSWorkspace.shared.menuBarOwningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let target = CopyPathTarget(processID: app.processIdentifier, bundleID: app.bundleIdentifier)
        if target.browser != nil,
           let addresses = try? await CopyPathSystemReader.read(.browser(target)),
           let address = ShortenLinkService.pick(argument: "", frontAddress: addresses.first, clipboard: nil) {
            return address
        }
        guard !Task.isCancelled else { return nil }
        return AccessibilityText.selection(in: app)
    }
}
