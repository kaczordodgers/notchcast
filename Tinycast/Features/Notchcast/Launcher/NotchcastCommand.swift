import Foundation

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    var feature: NotchcastFeature? = nil
    var owner: SettingsTab? = .notchcast
    var legacyID: String?
    /// It opens a palette screen: hiding first would drop the back step and replay the island opening.
    var keepsPalette = false
    var isEnabled: @MainActor @Sendable () -> Bool = { true }
    let run: @MainActor @Sendable () -> Void

    var id: String { "command:nc-" + slug }

    var entry: AppEntry {
        AppEntry(id: legacyID ?? id, name: name,
                 url: URL(string: "notchcast://command/nc-" + slug)!, bundleID: nil,
                 kind: .command, settingsOwner: owner, symbolName: sfSymbol)
    }
}
