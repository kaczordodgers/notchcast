import AppKit

@MainActor
final class SpacesOrderModule: NotchcastModule {
    private let defaults = UserDefaults(suiteName:
        (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!
    private let backupKey = "spacesOrderOriginal"
    private let domain = "com.apple.dock" as CFString
    private let key = "mru-spaces" as CFString
    private var task: Task<Void, Never>?
    private var restartPending = false
    var onFailure: (() -> Void)?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.apply(enabled: true)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        apply(enabled: false)
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
        if enabled && defaults.string(forKey: backupKey) == nil {
            defaults.set(current.rawValue, forKey: backupKey)
        }
        let original = defaults.string(forKey: backupKey).flatMap(SpacesOrderEngine.Value.init(rawValue:))
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
            let docks = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            guard docks.allSatisfy({ $0.terminate() }) else {
                onFailure?()
                return
            }
            restartPending = false
        }
        if !enabled { defaults.removeObject(forKey: backupKey) }
    }
}
