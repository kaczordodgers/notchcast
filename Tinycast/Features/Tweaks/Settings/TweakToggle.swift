import Foundation

/// One catalog tweak a Settings section switches; its writes and restart come from that catalog.
struct TweakToggle: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let writes: [TypingPreferencePlan.Write]
    let restart: String?
}

extension TweakToggle {
    static var typing: [Self] {
        [
            typing("autocorrect", LocalizedStringResource("Disable autocorrect", table: "Notchcast")),
            typing("smart-punctuation", LocalizedStringResource("Disable smart punctuation", table: "Notchcast")),
            typing("double-space-period", LocalizedStringResource("Disable double-space period", table: "Notchcast")),
            typing("auto-capitalize", LocalizedStringResource("Disable auto-capitalization", table: "Notchcast")),
            typing("key-repeat", LocalizedStringResource("Enable key repeat", table: "Notchcast")),
        ]
    }

    static var finder: [Self] {
        [
            finder("file-extensions", LocalizedStringResource("Show file extensions", table: "Notchcast")),
            finder("hidden-files", LocalizedStringResource("Show hidden files", table: "Notchcast")),
            finder("path-bar", LocalizedStringResource("Show path bar", table: "Notchcast")),
            finder("status-bar", LocalizedStringResource("Show status bar", table: "Notchcast")),
            finder("folders-first", LocalizedStringResource("Keep folders first", table: "Notchcast")),
            finder("search-this-folder", LocalizedStringResource("Search current folder", table: "Notchcast")),
            finder("extension-warning", LocalizedStringResource("Disable extension warning", table: "Notchcast")),
            finder("path-in-title", LocalizedStringResource("Show path in title", table: "Notchcast")),
            finder("network-ds-store", LocalizedStringResource("Avoid network metadata", table: "Notchcast")),
            finder("trash-30-days", LocalizedStringResource("Remove trash after 30 days", table: "Notchcast")),
            finder("save-locally", LocalizedStringResource("Save locally", table: "Notchcast")),
            finder("expanded-save", LocalizedStringResource("Expand save dialogs", table: "Notchcast")),
            finder("list-view", LocalizedStringResource("Use list view", table: "Notchcast")),
            finder("usb-ds-store", LocalizedStringResource("Avoid USB metadata", table: "Notchcast")),
            finder("desktop-disks", LocalizedStringResource("Hide desktop disks", table: "Notchcast")),
        ]
    }

    static var dock: [Self] {
        [
            dock("dock-recents", LocalizedStringResource("Hide recent apps", table: "Notchcast")),
            dock("dock-delay", LocalizedStringResource("Remove auto-hide delay", table: "Notchcast")),
            dock("dock-bounce", LocalizedStringResource("Disable launch animation", table: "Notchcast")),
            dock("minimize-to-app", LocalizedStringResource("Minimize into app", table: "Notchcast")),
            dock("window-animations", LocalizedStringResource("Disable window animations", table: "Notchcast")),
            dock("tile-margins", LocalizedStringResource("Remove tiled window margins", table: "Notchcast")),
            dock("screenshot-shadow", LocalizedStringResource("Remove screenshot shadow", table: "Notchcast")),
            dock("click-to-desktop", LocalizedStringResource("Disable click to desktop", table: "Notchcast")),
            dock("desktop-widgets", LocalizedStringResource("Hide desktop widgets", table: "Notchcast")),
        ]
    }

    private static func typing(_ id: String, _ title: LocalizedStringResource) -> Self {
        Self(id: id, title: title, writes: TypingCatalog.writes[id] ?? [], restart: nil)
    }

    private static func finder(_ id: String, _ title: LocalizedStringResource) -> Self {
        Self(id: id, title: title, writes: FinderCatalog.writes[id] ?? [],
             restart: FinderCatalog.requiresFinderRestart.contains(id) ? "Finder" : nil)
    }

    private static func dock(_ id: String, _ title: LocalizedStringResource) -> Self {
        Self(id: id, title: title, writes: DockCatalog.writes[id] ?? [], restart: DockCatalog.restartProcess(for: id))
    }
}
