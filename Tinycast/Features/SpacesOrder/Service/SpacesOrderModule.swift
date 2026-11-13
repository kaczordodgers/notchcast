import AppKit

@MainActor
final class SpacesOrderModule: NotchcastModule {
    private let defaults: UserDefaults
    nonisolated static let backupKey = "spacesOrderOriginal"
    private let domain: CFString
    private let sleep: () async -> Void
    private let restart: () -> Bool
    private let key = "mru-spaces" as CFString
    private var task: Task<Void, Never>?
    private var restartPending = false
    private var enabled = false
    var onFailure: (() -> Void)?

    init(defaults: UserDefaults = NotchcastIdentity.current.defaults, domain: String = "com.apple.dock",
         sleep: @escaping () async -> Void = { try? await Task.sleep(for: .seconds(30)) },
         restart: @escaping () -> Bool = {
             NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").allSatisfy { $0.terminate() }
         }) {
        self.defaults = defaults
        self.domain = domain as CFString
        self.sleep = sleep
        self.restart = restart
    }

    func start() {
        enabled = true
        apply(enabled: true)
        keepApplying()
    }

    func stop() {
        enabled = false
        apply(enabled: false)
        keepApplying()
    }

    private func keepApplying() {
        guard task == nil, enabled || restartPending else { return }
        let sleep = sleep
        task = Task { [weak self] in
            while true {
                await sleep()
                guard let self else { return }
                guard enabled || restartPending else { task = nil; return }
                apply(enabled: enabled)
            }
        }
    }

    func restoreIfDisabled() {
        if !NotchcastPreferences.shared.isOn(.spacesOrder) { apply(enabled: false) }
    }

    private func apply(enabled: Bool) {
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            onFailure?()
            return
        }
        let value = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let current: SpacesOrderEngine.Value = value == nil ? .absent
            : ((value as? Bool) == false ? .disabled : .enabled)
        if enabled && defaults.string(forKey: Self.backupKey) == nil {
            defaults.set(current.rawValue, forKey: Self.backupKey)
        }
        let original = defaults.string(forKey: Self.backupKey).flatMap(SpacesOrderEngine.Value.init(rawValue:))
        let target = SpacesOrderEngine.target(enabled: enabled, original: original)
        if SpacesOrderEngine.needsWrite(current: current, target: target), let target {
            let replacement: CFPropertyList? = target == .absent ? nil : NSNumber(value: target == .enabled)
            CFPreferencesSetValue(key, replacement, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
                onFailure?()
                return
            }
            restartPending = true
        }
        if restartPending {
            guard restart() else {
                onFailure?()
                return
            }
            restartPending = false
        }
        if !enabled { defaults.removeObject(forKey: Self.backupKey) }
    }
}
