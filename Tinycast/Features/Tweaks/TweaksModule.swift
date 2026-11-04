import Foundation
import AppKit

@MainActor
final class TweaksModule: NotchcastModule {
    let store: TweaksStore
    private weak var core: AppCore?
    private var stopping: Task<Void, Never>?
    private var wantsEnabled = false
    private let profileRunner: (Data, String) async throws -> Void
    private let journalFailure: String?

    init(key: String, profileRunner: @escaping (Data, String) async throws -> Void = TweaksModule.openProfile) {
        self.profileRunner = profileRunner
        let defaults = UserDefaults(suiteName:
            (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!
        let data = defaults.data(forKey: key)
        var plans: [String: TypingPreferencePlan] = [:]
        do {
            if let data { plans = try JSONDecoder().decode([String: TypingPreferencePlan].self, from: data) }
            journalFailure = nil
        } catch { journalFailure = error.localizedDescription }
        store = TweaksStore(plans: plans, read: TypingPreferenceService().readPreference,
                            run: Self.run, save: { plans in
            defaults.set(try JSONEncoder().encode(plans), forKey: key)
        })
    }

    func configure(_ core: AppCore) {
        self.core = core
        if let journalFailure { core.showMessage(journalFailure) }
    }
    func start() {
        guard journalFailure == nil else { return }
        wantsEnabled = true
        if stopping == nil { store.start() }
    }

    func setFeature(_ feature: NotchcastFeature, enabled: Bool) async {
        guard let core, !store.busy else { return }
        if !enabled, !store.plans.isEmpty {
            guard await core.confirm(title: feature.title,
                message: String(localized: "Restore the captured preferences before disabling this feature?"),
                symbol: "arrow.uturn.backward", confirmTitle: String(localized: "Restore")) else { return }
        }
        NotchcastPreferences.shared.set(feature, enabled)
    }

    func stop() {
        wantsEnabled = false
        store.suspend()
        guard stopping == nil else { return }
        stopping = Task { [weak self] in
            guard let self else { return }
            do { try await store.stop() } catch { core?.showMessage(error.localizedDescription) }
            stopping = nil
            if wantsEnabled { store.start() }
        }
    }

    func showLibrary() async {
        guard let core, store.enabled, !store.busy,
              await core.confirm(title: String(localized: "Show library"),
                  message: String(localized: "Make your Library folder visible in Finder."),
                  symbol: "folder", confirmTitle: String(localized: "Apply")), store.enabled else { return }
        do {
            try await store.apply("show-library") {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let hidden = try FinderService().libraryHidden(home: home)
                return .init(entries: [], extraApply: [FinderCatalog.library(home: home, hidden: false)],
                             extraRevert: [FinderCatalog.library(home: home, hidden: hidden)])
            }
        } catch { core.showMessage(error.localizedDescription) }
    }

    func handOffProfile(_ restriction: AppleAppsPolicy.Restriction) async {
        guard let core, store.enabled, !store.busy,
              await core.confirm(title: String(localized: "Review configuration profile"),
                  message: String(localized:
                    "macOS requires your approval to install this restriction; remove it in System Settings."),
                  symbol: "gearshape", confirmTitle: String(localized: "Open…")),
              store.enabled else { return }
        do {
            let identifier = (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + "." + restriction.rawValue
            let data = try AppleAppsPolicy.profile([restriction], identifier: identifier,
                profileUUID: UUID(), payloadUUID: UUID())
            try await profileRunner(data, identifier)
        } catch { core.showMessage(error.localizedDescription) }
    }

    @concurrent
    private static func openProfile(_ data: Data, identifier: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Restriction.mobileconfig")
        try data.write(to: file, options: .atomic)
        try await run([.init(executable: "/usr/bin/open", arguments: [file.path])])
    }

    func set(_ identifier: String, writes: [TypingPreferencePlan.Write], on: Bool,
             title: String, subtitle: String, restart: String?) async {
        guard let core, store.enabled, !store.busy,
              await core.confirm(title: title, message: subtitle, symbol: "gearshape",
                                 confirmTitle: String(localized: "Apply")),
              store.enabled, !Task.isCancelled else { return }
        do {
            try await store.set(identifier, writes: writes, on: on)
            if let restart, store.enabled {
                try await Self.run([.init(executable: "/usr/bin/killall", arguments: [restart])])
            }
        } catch { core.showMessage(error.localizedDescription) }
    }

    @concurrent
    private static func run(_ commands: [TypingPreferencePlan.Command]) async throws {
        for command in commands {
            try Task.checkCancellation()
            let process = Process()
            process.executableURL = URL(filePath: command.executable)
            process.arguments = command.arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let exit = try process.runObservingExit()
            exit.wait()
            guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        }
    }
}
