import AppKit
import Foundation
import Observation
import Synchronization
import SwiftUI

@main @MainActor
struct AppearanceThemesTest {
    nonisolated static func token() -> Color {
        AppearanceThemeColors.shared.ramp(dark: 0.4, light: 0.5)
    }

    static var checks = 0

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { fatalError(message) }
    }

    static func link(
        name: String = "Test", appearance: String = "dark", colors: [String]? = nil,
        extra: [URLQueryItem] = [], scheme: String = "raycast"
    ) -> URL {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = "theme"
        parts.queryItems = [
            .init(name: "name", value: name), .init(name: "authorUsername", value: "Author"),
            .init(name: "appearance", value: appearance),
            .init(name: "colors", value: (colors ?? Array(repeating: "#123456", count: 12)).joined(separator: ","))
        ] + extra
        guard let url = parts.url else { fatalError("fixture URL") }
        return url
    }

    static func parsed(_ url: URL) -> RaycastThemeLink? {
        RaycastThemeLink(url: url, applicationScheme: "notchcast-dev")
    }

    static func parsing() throws {
        expect(RaycastThemeCatalog.all.count > 70, "full bundled catalog")
        expect(RaycastThemeCatalog.all.allSatisfy(\.isValid), "catalog validates")
        expect(Set(RaycastThemeCatalog.all.map(\.id)).count == RaycastThemeCatalog.all.count, "unique catalog IDs")
        expect(RaycastTheme.hex6(" #abcdef80 ") == "#ABCDEF", "discard Theme Studio alpha")
        expect(RaycastTheme.hex6("#１２３４５６") == nil, "ASCII hex only")
        expect(RaycastTheme.hex6("123456") == nil, "require hash")
        expect(RaycastTheme.hex6("#12345G") == nil, "reject invalid hex")
        let url = link(name: "A & B, 日本語")
        expect(parsed(url)?.target.theme?.name == "A & B, 日本語", "URL decoding")
        expect(parsed(url)?.target.theme?.author == "Author", "authorUsername fallback")
        expect(parsed(link(scheme: "notchcast-dev")) != nil, "injected app scheme")
        expect(parsed(link(scheme: "notchcast")) == nil, "channel isolation")
        expect(parsed(link(scheme: "https")) == nil, "reject web URLs")
        expect(parsed(link(name: "  \n")) == nil, "reject empty names")
        expect(parsed(link(appearance: "system")) == nil, "require concrete slot")
        expect(parsed(link(colors: Array(repeating: "#123456", count: 11))) == nil, "require twelve colors")
        expect(parsed(link(colors: Array(repeating: "#123456", count: 13))) == nil, "reject extra color")
        let invalid = Array(repeating: "#123456", count: 12) + ["broken"]
        expect(parsed(link(colors: invalid)) == nil, "do not compact away invalid colors")
        expect(parsed(link(colors: [""] + Array(repeating: "#123456", count: 11))) == nil, "reject empty color")
        expect(parsed(link(extra: [.init(name: "name", value: "Other")])) == nil, "reject duplicate fields")
        expect(parsed(link(extra: [.init(name: "none", value: "dark")])) == nil, "reject ambiguous targets")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/other"
        expect(components?.url.flatMap(parsed) == nil, "reject extra path")
        components?.path = ""
        components?.user = "user"
        expect(components?.url.flatMap(parsed) == nil, "reject user info")
        guard let reset = URL(string: "raycast://theme?none=light&apply=1") else { fatalError("reset URL") }
        expect(parsed(reset)?.target == .tinycast(.light), "reset target")
        expect(parsed(reset)?.applies == true, "preserve command intent without authorizing it")
        let theme = RaycastThemeCatalog.all[0]
        expect(try JSONDecoder().decode(RaycastTheme.self, from: JSONEncoder().encode(theme)) == theme, "Codable")
        let badTheme = RaycastTheme(name: "Bad", author: "", appearance: .dark, colors: [])
        do {
            _ = try JSONDecoder().decode(RaycastTheme.self, from: JSONEncoder().encode(badTheme))
            fatalError("invalid saved theme decoded")
        } catch RaycastTheme.ValidationError.invalidTheme {
            expect(true, "invalid saved theme rejected")
        }
    }

    @MainActor
    static func storage(defaults: UserDefaults) throws {
        let store = AppearanceStore(defaults: defaults)
        expect(store.light == nil && store.dark == nil && store.imported.isEmpty, "fresh store")
        expect(store.surfaceStyle == .glass && store.backgroundOpacity == 0.7, "upstream defaults")
        expect(defaults.object(forKey: AppearanceStore.darkKey) == nil, "reading does not persist defaults")
        let dark = RaycastTheme(name: "Paired", author: "Author", appearance: .dark,
                                colors: Array(repeating: "#12345680", count: 12))
        let light = RaycastTheme(name: "Paired", author: "Author", appearance: .light,
                                 colors: Array(repeating: "#ABCDEF", count: 12))
        try store.install(dark)
        try store.install(light)
        expect(store.imported.count == 2, "same name may have light and dark variants")
        try store.add(dark)
        expect(store.imported.count == 2 && store.imported.first == dark, "deduplicate newest import")
        store.surfaceStyle = .matte
        let surfacePreference = AppStorage(
            wrappedValue: AppearanceSurfaceStyle.glass,
            AppearanceSurfaceStyle.defaultsKey, store: defaults)
        expect(surfacePreference.wrappedValue == .matte, "surface reads the store's suite")
        surfacePreference.wrappedValue = .black
        expect(AppearanceStore(defaults: defaults).surfaceStyle == .black, "surface writes the same suite")
        store.surfaceStyle = .black
        store.surfaceStyle = .matte
        store.backgroundOpacity = 0.8
        let restored = AppearanceStore(defaults: defaults)
        expect(restored.dark == dark && restored.light == light, "both slots persist")
        expect(restored.surfaceStyle == .matte && restored.backgroundOpacity == 0.8, "fork preferences persist")
        do {
            try store.select(dark, for: .light)
            fatalError("wrong slot accepted")
        } catch RaycastTheme.ValidationError.wrongAppearance {
            expect(store.light == light, "wrong slot leaves state intact")
        }
        do {
            try store.add(RaycastTheme(name: "Bad", author: "", appearance: .dark, colors: []))
            fatalError("invalid theme accepted")
        } catch RaycastTheme.ValidationError.invalidTheme {
            expect(store.imported.count == 2, "invalid import leaves library intact")
        }
        store.backgroundOpacity = .nan
        expect(store.backgroundOpacity == 0.8, "ignore NaN opacity")
        store.backgroundOpacity = 5
        expect(store.backgroundOpacity == 1, "upper opacity bound")
        store.backgroundOpacity = -5
        expect(store.backgroundOpacity == 0.2, "lower opacity bound")
        try store.remove(dark)
        expect(store.dark == nil && store.light == light && store.imported == [light], "remove only matching slot")
        defaults.set(Data("broken".utf8), forKey: AppearanceStore.darkKey)
        defaults.set(try JSONEncoder().encode(dark), forKey: AppearanceStore.lightKey)
        defaults.set("unknown", forKey: AppearanceSurfaceStyle.defaultsKey)
        defaults.set(Double.infinity, forKey: AppearanceStore.opacityKey)
        let damaged = AppearanceStore(defaults: defaults)
        expect(damaged.light == nil && damaged.dark == nil, "bad persisted slots safely ignored")
        expect(Set(damaged.invalidPreferenceKeys) == [AppearanceStore.lightKey, AppearanceStore.darkKey],
               "bad preferences available for reporting")
        expect(damaged.surfaceStyle == .glass && damaged.backgroundOpacity == 0.7, "bad preferences use defaults")
    }

    @MainActor
    static func imports(defaults: UserDefaults) throws {
        let store = AppearanceStore(defaults: defaults)
        let url = link(extra: [.init(name: "apply", value: "1")])
        guard let first = store.requestImport(url: url, applicationScheme: "notchcast-dev") else {
            fatalError("missing import request")
        }
        expect(store.dark == nil && store.imported.isEmpty, "external apply flag still asks")
        expect(store.requestImport(url: url, applicationScheme: "notchcast-dev") == nil, "one pending dialog")
        try store.resolveImport(id: UUID(), choice: .useTheme)
        expect(store.pendingImport == first && store.dark == nil, "stale response ignored")
        try store.resolveImport(id: first.id, choice: .cancel)
        expect(store.pendingImport == nil && store.imported.isEmpty, "cancel has no persisted effect")
        guard let second = store.requestImport(url: url, applicationScheme: "notchcast-dev") else {
            fatalError("second request")
        }
        try store.resolveImport(id: first.id, choice: .useTheme)
        expect(store.pendingImport == second, "old dialog cannot consume new import")
        try store.resolveImport(id: second.id, choice: .justAdd)
        expect(store.dark == nil && store.imported.count == 1, "Just Add only changes library")
        guard let third = store.requestImport(url: url, applicationScheme: "notchcast-dev") else {
            fatalError("third request")
        }
        try store.resolveImport(id: third.id, choice: .useTheme)
        expect(store.dark == third.target.theme && store.pendingImport == nil, "Use Theme installs")
        guard let resetURL = URL(string: "raycast://theme?none=dark"),
            let reset = store.requestImport(url: resetURL, applicationScheme: "notchcast-dev")
        else { fatalError("reset request") }
        try store.resolveImport(id: reset.id, choice: .useTheme)
        expect(store.dark == nil && store.imported.count == 1, "reset keeps library")
    }

    @MainActor
    static func previewAndColors(defaults: UserDefaults) throws {
        let store = AppearanceStore(defaults: defaults)
        guard let darkAppearance = NSAppearance(named: .darkAqua), let lightAppearance = NSAppearance(named: .aqua)
        else { fatalError("native appearances") }
        let dark = RaycastThemeCatalog.all.first { $0.appearance == .dark }
        let light = RaycastThemeCatalog.all.first { $0.appearance == .light }
        guard let dark, let light else { fatalError("catalog slots") }
        expect(store.colors.ink(.text, in: darkAppearance, dark: 0.4, light: 0.5) == nil, "no theme uses upstream")
        try store.select(dark, for: .dark)
        try store.select(light, for: .light)
        expect(store.colors.ink(.text, in: darkAppearance, dark: 0.4, light: 0.5)?.alphaComponent == 0.4,
               "dark token alpha retained")
        expect(store.colors.ink(.selection, in: lightAppearance, dark: 0.1, light: 0.09)?.alphaComponent == 0.09,
               "light selection alpha retained")
        expect(store.colors.ink(.background, in: darkAppearance, dark: 1, light: 1)?.alphaComponent == 0.7,
               "backdrop opacity is independent of token alpha")
        let dynamic = store.colors.dynamicColor(.text, dark: 0.4, light: 0.5, fallback: .clear)
        let saved = defaults.data(forKey: AppearanceStore.darkKey)
        let before = store.revision
        let observed = Mutex(false)
        withObservationTracking {
            _ = token()
        } onChange: {
            observed.withLock { $0 = true }
        }
        store.preview(.tinycast(.dark))
        expect(observed.withLock { $0 }, "drawing a ramp token observes the revision")
        expect(store.revision > before && store.dark == dark, "preview bumps revision without selection")
        expect(store.colors.ink(.text, in: darkAppearance, dark: 0.4, light: 0.5) == nil,
               "Tinycast preview differs from no preview")
        expect(store.colors.ink(.text, in: lightAppearance, dark: 0.4, light: 0.5) != nil,
               "preview leaves opposite slot intact")
        store.preview(.theme(light))
        expect(store.previewTarget?.appearance == .light, "preview exposes appearance for window owner")
        expect(defaults.data(forKey: AppearanceStore.darkKey) == saved, "preview never persists")
        store.preview(nil)
        expect(store.colors.ink(.text, in: darkAppearance, dark: 0.4, light: 0.5) != nil, "ending preview restores")
        try store.select(nil, for: .dark)
        var alpha: CGFloat = -1
        darkAppearance.performAsCurrentDrawingAppearance { alpha = dynamic.alphaComponent }
        expect(alpha == 0, "existing dynamic colors resolve new state")
        _ = AppearanceThemeColors.shared.ramp(dark: 0.4, light: 0.5)
        _ = store.backdrop
    }

    static func listings() {
        let theme = RaycastThemeCatalog.all[0]
        let variant = RaycastTheme(name: theme.name, author: theme.author, appearance: .light, colors: theme.colors)
        let sections = AppearanceThemeBrowser.themes(for: theme.appearance, query: "", imported: [theme, variant])
        expect(sections.imported == [theme], "browser filters slot")
        expect(!sections.bundled.contains(theme), "import replaces catalog copy")
        let matching = AppearanceThemeBrowser.themes(for: theme.appearance, query: "  \(theme.author)  ", imported: [theme])
        expect(matching.imported == [theme], "author search trims whitespace")
        let rows = AppearanceThemeCommand.rows(currentAppearance: .dark, light: variant, dark: theme, imported: [theme])
        expect(rows.first?.target.appearance == .dark, "current slot first")
        expect(rows.count == 4 && rows.filter(\.isSelected).count == 2, "native rows include both selected slots")
        expect(Set(rows.map(\.id)).count == rows.count, "stable command row IDs")
        expect(AppearanceThemeCommand.rows(currentAppearance: .dark, light: nil, dark: nil,
                                          imported: [], query: "missing").isEmpty, "command search")
    }

    @MainActor
    static func main() throws {
        try parsing()
        listings()
        for test in [storage, imports, previewAndColors] {
            let domain = "nc-Appearance-tests-\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: domain) else { fatalError("private defaults") }
            defer { defaults.removePersistentDomain(forName: domain) }
            try test(defaults)
        }
        print("\(checks) appearance theme checks passed; private defaults only")
    }
}
