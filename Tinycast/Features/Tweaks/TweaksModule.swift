import Foundation
import AppKit

@MainActor
final class TweaksModule: NotchcastModule {
    private(set) var running = false
    private let setupProfileRunner: TweakProfileRunner
    let store: TweaksStore
    private weak var core: AppCore?
    private var stopping: Task<Void, Never>?
    private var wantsEnabled = false
    private let profileRunner: (Data, String) async throws -> Void
    private let journalFailure: String?

    init(key: String = "macSetupPlans", setupProfileRunner: TweakProfileRunner = .system,
         profileRunner: @escaping (Data, String) async throws -> Void = TweaksModule.openProfile) {
        self.setupProfileRunner = setupProfileRunner
        self.profileRunner = profileRunner
        let defaults = NotchcastIdentity.current.defaults
        let data = defaults.data(forKey: key)
        var plans: [String: TypingPreferencePlan] = [:]
        var decodedJournal = data == nil
        do {
            if let data {
                guard let entries = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw SystemToolsProcessRunner.Failure.invalidExecutable
                }
                for (identifier, entry) in entries {
                    guard let encoded = try? JSONSerialization.data(withJSONObject: entry, options: .fragmentsAllowed),
                          let plan = try? JSONDecoder().decode(TypingPreferencePlan.self, from: encoded),
                          plan.permitsJournal(home: NSHomeDirectory()) else { continue }
                    plans[identifier] = plan
                }
                decodedJournal = entries.isEmpty || !plans.isEmpty
                guard decodedJournal else { throw SystemToolsProcessRunner.Failure.invalidExecutable }
                if plans.count != entries.count {
                    defaults.set(try JSONEncoder().encode(plans), forKey: key)
                    throw SystemToolsProcessRunner.Failure.invalidExecutable
                }
            }
            journalFailure = nil
        } catch {
            journalFailure = error.localizedDescription
        }
        let canSave = decodedJournal
        store = TweaksStore(plans: plans, read: TypingPreferenceService().readPreference,
                            run: Self.run, save: { plans in
            guard canSave else { throw SystemToolsProcessRunner.Failure.invalidExecutable }
            defaults.set(try JSONEncoder().encode(plans), forKey: key)
        })
    }

    func configure(_ core: AppCore) {
        self.core = core
        if let journalFailure { core.showMessage(journalFailure) }
    }
    func start() {
        running = true
        wantsEnabled = true
        if stopping == nil { store.start() }
    }

    func setFeature(_ feature: NotchcastFeature, enabled: Bool) async {
        guard let core, !store.busy else { return }
        if !enabled, !store.plans.isEmpty {
            guard await core.confirm(title: feature.title,
                message: String(localized: "Restore the captured preferences before disabling this feature?", table: "Notchcast"),
                symbol: "arrow.uturn.backward", confirmTitle: String(localized: "Restore", table: "Notchcast")) else { return }
        }
        NotchcastPreferences.shared.set(feature, enabled)
    }

    func stop() {
        running = false
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

    func requestProfile(keepingAI: Set<String>?, privacy: Set<String>) async throws -> URL {
        guard running, let identifier = Bundle.main.bundleIdentifier else {
            throw CocoaError(.userCancelled)
        }
        let data = try TweakProfile.data(bundleIdentifier: identifier, keepingAI: keepingAI, privacy: privacy)
        let folder = URL.cachesDirectory.appending(path: identifier).appending(path: "TweakProfiles")
        return try await setupProfileRunner.requestApproval(data: data, folder: folder)
    }

    func showLibrary() async {
        guard let core, store.enabled, !store.busy,
              await core.confirm(title: String(localized: "Show library", table: "Notchcast"),
                  message: String(localized: "Make your Library folder visible in Finder.", table: "Notchcast"),
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
              await core.confirm(title: String(localized: "Review configuration profile", table: "Notchcast"),
                  message: String(localized:
                    "macOS requires your approval to install this restriction; remove it in System Settings.", table: "Notchcast"),
                  symbol: "gearshape", confirmTitle: String(localized: "Open…")),
              store.enabled else { return }
        do {
            let identifier = NotchcastIdentity.current.suiteName(suffix: "." + restriction.rawValue)
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
        guard commands.allSatisfy({ SystemToolsProcessRunner.allowedExecutables.contains($0.executable) }) else {
            throw SystemToolsProcessRunner.Failure.invalidExecutable
        }
        for command in commands {
            try Task.checkCancellation()
            _ = try SystemToolsProcessRunner().run(command.executable, arguments: command.arguments)
        }
    }
}

extension TweakProfileRunner {
    static let system = Self { file in
        _ = try SystemToolsProcessRunner().run("/usr/bin/open", arguments: [file.path])
    }
}
