import Foundation
import Observation

@MainActor @Observable
final class AppearanceStore {
    private(set) static weak var current: AppearanceStore?
    static let preferences = UserDefaults(
        suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!
    static let lightKey = "notchcast.appearance.theme.light"
    static let darkKey = "notchcast.appearance.theme.dark"
    static let importedKey = "notchcast.appearance.themes.imported"
    static let opacityKey = "notchcast.appearance.theme.backgroundOpacity"
    nonisolated static let defaultOpacity = 0.7

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let colors = AppearanceThemeColors.shared

    private(set) var light: RaycastTheme?
    private(set) var dark: RaycastTheme?
    private(set) var imported: [RaycastTheme]
    private(set) var previewTarget: RaycastThemeLink.Target?
    private(set) var pendingImport: AppearanceThemeImport?
    private(set) var isEnabled: Bool
    private(set) var revision = 0
    let invalidPreferenceKeys: [String]

    var surfaceStyle: AppearanceSurfaceStyle {
        didSet {
            guard oldValue != surfaceStyle else { return }
            defaults.set(surfaceStyle.rawValue, forKey: AppearanceSurfaceStyle.defaultsKey)
            revision &+= 1
        }
    }

    private var opacity: Double

    var backgroundOpacity: Double {
        get { opacity }
        set {
            guard newValue.isFinite else { return }
            let bounded = min(1, max(0.2, newValue))
            guard bounded != opacity else { return }
            defaults.set(bounded, forKey: Self.opacityKey)
            opacity = bounded
            refreshColors()
        }
    }

    var effectiveSurfaceStyle: AppearanceSurfaceStyle { isEnabled ? surfaceStyle : .glass }

    init(defaults: UserDefaults = AppearanceStore.preferences, enabled: Bool = true) {
        self.defaults = defaults
        isEnabled = enabled
        var invalidKeys: [String] = []
        func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
            guard let raw = defaults.object(forKey: key) else { return nil }
            guard let data = raw as? Data, let result = try? JSONDecoder().decode(type, from: data) else {
                invalidKeys.append(key)
                return nil
            }
            return result
        }
        let savedLight = decode(RaycastTheme.self, key: Self.lightKey)
        let savedDark = decode(RaycastTheme.self, key: Self.darkKey)
        if let savedLight, savedLight.appearance != .light { invalidKeys.append(Self.lightKey) }
        if let savedDark, savedDark.appearance != .dark { invalidKeys.append(Self.darkKey) }
        light = savedLight?.appearance == .light ? savedLight : nil
        dark = savedDark?.appearance == .dark ? savedDark : nil
        let savedImports = decode([RaycastTheme].self, key: Self.importedKey) ?? []
        var identities: Set<String> = []
        imported = savedImports.filter { identities.insert($0.id).inserted }
        surfaceStyle = defaults.string(forKey: AppearanceSurfaceStyle.defaultsKey)
            .flatMap(AppearanceSurfaceStyle.init(rawValue:)) ?? .glass
        let savedOpacity = defaults.object(forKey: Self.opacityKey) as? Double
        opacity = savedOpacity.flatMap { $0.isFinite ? min(1, max(0.2, $0)) : nil } ?? Self.defaultOpacity
        invalidPreferenceKeys = invalidKeys
        for key in invalidKeys { defaults.removeObject(forKey: key) }
        refreshColors()
        Self.current = self
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        previewTarget = nil
        pendingImport = nil
        refreshColors()
    }

    func theme(for slot: RaycastTheme.Appearance) -> RaycastTheme? {
        slot == .dark ? dark : light
    }

    func select(_ theme: RaycastTheme?, for slot: RaycastTheme.Appearance) throws {
        if let theme {
            guard theme.isValid else { throw RaycastTheme.ValidationError.invalidTheme }
            guard theme.appearance == slot else { throw RaycastTheme.ValidationError.wrongAppearance }
        }
        let key = slot == .dark ? Self.darkKey : Self.lightKey
        if let theme {
            defaults.set(try JSONEncoder().encode(theme), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        if slot == .dark { dark = theme } else { light = theme }
        previewTarget = nil
        refreshColors()
    }

    func add(_ theme: RaycastTheme) throws {
        guard theme.isValid else { throw RaycastTheme.ValidationError.invalidTheme }
        let next = [theme] + imported.filter { $0.id != theme.id }
        defaults.set(try JSONEncoder().encode(next), forKey: Self.importedKey)
        imported = next
    }

    func replaceImported(_ themes: [RaycastTheme]) throws {
        guard themes.allSatisfy(\.isValid) else { throw RaycastTheme.ValidationError.invalidTheme }
        defaults.set(try JSONEncoder().encode(themes), forKey: Self.importedKey)
        imported = themes
    }

    func install(_ theme: RaycastTheme) throws {
        try add(theme)
        try select(theme, for: theme.appearance)
    }

    func remove(_ theme: RaycastTheme) throws {
        let next = imported.filter { $0.id != theme.id }
        defaults.set(try JSONEncoder().encode(next), forKey: Self.importedKey)
        imported = next
        if self.theme(for: theme.appearance)?.id == theme.id {
            try select(nil, for: theme.appearance)
        } else if previewTarget?.theme?.id == theme.id {
            preview(nil)
        }
    }

    func preview(_ target: RaycastThemeLink.Target?) {
        guard isEnabled, target != previewTarget, target?.theme?.isValid != false else { return }
        previewTarget = target
        refreshColors()
    }

    func requestImport(url: URL, applicationScheme: String) -> AppearanceThemeImport? {
        guard isEnabled, pendingImport == nil,
            let link = RaycastThemeLink(url: url, applicationScheme: applicationScheme)
        else { return nil }
        // A URL's apply flag is untrusted; only a native command action may apply without a dialog.
        let request = AppearanceThemeImport(id: UUID(), target: link.target)
        pendingImport = request
        return request
    }

    func resolveImport(id: UUID, choice: AppearanceThemeImport.Choice) throws {
        guard let request = pendingImport, request.id == id else { return }
        switch choice {
        case .useTheme:
            if let theme = request.target.theme {
                try install(theme)
            } else {
                try select(nil, for: request.target.appearance)
            }
        case .justAdd:
            if let theme = request.target.theme { try add(theme) }
        case .cancel:
            break
        }
        pendingImport = nil
    }

    private func refreshColors() {
        colors.update(
            light: isEnabled ? light : nil, dark: isEnabled ? dark : nil,
            preview: isEnabled ? previewTarget : nil, opacity: opacity)
        revision &+= 1
    }
}
