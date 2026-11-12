import Foundation
import AppKit

@MainActor
final class TweaksModule: NotchcastModule {
    private(set) var running = false
    private let setupProfileRunner: TweakProfileRunner
    let store: TweaksStore
    private var stopping: Task<Void, Never>?
    private var wantsEnabled = false
    private let profileRunner: (Data, String) async throws -> Void
    private let journalFailure: String?
    private var spotlightBusy = false
    private let preferences: NotchcastPreferences

    init(key: String = "macSetupPlans", setupProfileRunner: TweakProfileRunner = .system,
         preferences: NotchcastPreferences = .shared,
         profileRunner: @escaping (Data, String) async throws -> Void = TweaksModule.openProfile) {
        self.setupProfileRunner = setupProfileRunner
        self.profileRunner = profileRunner
        self.preferences = preferences
        let defaults = NotchcastIdentity.current.defaults
        let (plans, failure) = TweaksJournal.load(defaults.data(forKey: key), home: NSHomeDirectory())
        if failure == .entriesDropped, let kept = try? JSONEncoder().encode(plans) { defaults.set(kept, forKey: key) }
        journalFailure = failure?.localizedDescription
        let canSave = failure != .unreadable
        store = TweaksStore(plans: plans, read: TypingPreferenceService().readPreference,
                            run: Self.run, save: { plans in
            guard canSave else { throw TweaksJournalFailure.unreadable }
            defaults.set(try JSONEncoder().encode(plans), forKey: key)
        })
    }

    func configure() {
        if let journalFailure { NotchcastHost.current.showMessage(journalFailure, .success) }
    }
    func start() {
        running = true
        wantsEnabled = true
        if stopping == nil { store.start() }
    }

    func setFeature(_ feature: NotchcastFeature, enabled: Bool) async {
        guard !store.busy else { return }
        if !enabled, !store.plans.isEmpty {
            guard await NotchcastHost.current.confirm(feature.title,
                String(localized: "Restore the captured preferences before disabling this feature?", table: "Notchcast"),
                "arrow.uturn.backward", String(localized: "Restore", table: "Notchcast")) else { return }
        }
        preferences.set(feature, enabled)
    }

    func setSpotlight(enabled: Bool) async {
        guard !spotlightBusy else { return }
        spotlightBusy = true
        defer { spotlightBusy = false }
        let feature = NotchcastFeature.spotlightOff
        guard await NotchcastHost.current.confirm(feature.title, feature.subtitle,
                                 "gearshape", feature.title),
              preferences.isOn(feature) != enabled else { return }
        do {
            _ = try await RootHelperClient().run(enabled ? .spotlightOff : .spotlightOn)
            preferences.set(feature, enabled)
        } catch { NotchcastHost.current.showMessage(error.localizedDescription, .danger) }
    }

    func stop() {
        running = false
        wantsEnabled = false
        store.suspend()
        guard stopping == nil else { return }
        stopping = Task { [weak self] in
            guard let self else { return }
            do { try await store.stop() } catch { NotchcastHost.current.showMessage(error.localizedDescription, .success) }
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
        guard store.enabled, !store.busy,
              await NotchcastHost.current.confirm(String(localized: "Show library", table: "Notchcast"),
                  String(localized: "Make your Library folder visible in Finder.", table: "Notchcast"),
                  "folder", String(localized: "Apply")), store.enabled else { return }
        do {
            try await store.apply("show-library") {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let hidden = try FinderService().libraryHidden(home: home)
                return .init(entries: [], extraApply: [FinderCatalog.library(home: home, hidden: false)],
                             extraRevert: [FinderCatalog.library(home: home, hidden: hidden)])
            }
        } catch { NotchcastHost.current.showMessage(error.localizedDescription, .success) }
    }

    func handOffProfile(_ restriction: AppleAppsPolicy.Restriction) async {
        guard store.enabled, !store.busy,
              await NotchcastHost.current.confirm(String(localized: "Review configuration profile", table: "Notchcast"),
                  String(localized:
                    "macOS requires your approval to install this restriction; remove it in System Settings.", table: "Notchcast"),
                  "gearshape", String(localized: "Open…")),
              store.enabled else { return }
        do {
            let identifier = NotchcastIdentity.current.bundleID + "." + restriction.rawValue
            let data = try AppleAppsPolicy.profile([restriction], identifier: identifier,
                profileUUID: UUID(), payloadUUID: UUID())
            try await profileRunner(data, identifier)
        } catch { NotchcastHost.current.showMessage(error.localizedDescription, .success) }
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
        guard store.enabled, !store.busy,
              await NotchcastHost.current.confirm(title, subtitle, "gearshape",
                                 String(localized: "Apply")),
              store.enabled, !Task.isCancelled else { return }
        do {
            try await store.set(identifier, writes: writes, on: on)
            if let restart, store.enabled {
                try await Self.run([.init(executable: "/usr/bin/killall", arguments: [restart])])
            }
        } catch { NotchcastHost.current.showMessage(error.localizedDescription, .success) }
    }

    @concurrent
    private static func run(_ commands: [TypingPreferencePlan.Command]) async throws {
        guard commands.allSatisfy({ TweaksProcessRunner.allowedExecutables.contains($0.executable) }) else {
            throw TweaksProcessRunner.Failure.invalidExecutable
        }
        for command in commands {
            try Task.checkCancellation()
            _ = try TweaksProcessRunner().run(command.executable, arguments: command.arguments)
        }
    }
}

extension TweakProfileRunner {
    static let system = Self { file in
        _ = try TweaksProcessRunner().run("/usr/bin/open", arguments: [file.path])
    }
}
