import Foundation

nonisolated enum FinderCatalog {
    typealias Write = TypingPreferencePlan.Write

    static let writes: [String: [Write]] = [
        "file-extensions": [Write("AppleShowAllExtensions", .bool(true))],
        "hidden-files": [Write("com.apple.finder", "AppleShowAllFiles", .bool(true))],
        "path-bar": [Write("com.apple.finder", "ShowPathbar", .bool(true))],
        "status-bar": [Write("com.apple.finder", "ShowStatusBar", .bool(true))],
        "folders-first": [Write("com.apple.finder", "_FXSortFoldersFirst", .bool(true))],
        "search-this-folder": [Write("com.apple.finder", "FXDefaultSearchScope", .string("SCcf"))],
        "extension-warning": [Write("com.apple.finder", "FXEnableExtensionChangeWarning", .bool(false))],
        "path-in-title": [Write("com.apple.finder", "_FXShowPosixPathInTitle", .bool(true))],
        "network-ds-store": [Write("com.apple.desktopservices", "DSDontWriteNetworkStores", .bool(true))],
        "trash-30-days": [Write("com.apple.finder", "FXRemoveOldTrashItems", .bool(true))],
        "save-locally": [Write("NSDocumentSaveNewDocumentsToCloud", .bool(false))],
        "expanded-save": [Write("NSNavPanelExpandedStateForSaveMode", .bool(true))],
        "list-view": [Write("com.apple.finder", "FXPreferredViewStyle", .string("Nlsv"))],
        "usb-ds-store": [Write("com.apple.desktopservices", "DSDontWriteUSBStores", .bool(true))],
        "desktop-disks": ["ShowHardDrivesOnDesktop", "ShowExternalHardDrivesOnDesktop",
                          "ShowRemovableMediaOnDesktop", "ShowMountedServersOnDesktop"].map {
            Write("com.apple.finder", $0, .bool(false))
        },
    ]
    static let preset: Set<String> = [
        "file-extensions", "path-bar", "folders-first", "search-this-folder", "extension-warning",
        "network-ds-store", "trash-30-days", "expanded-save", "show-library", "list-view",
        "usb-ds-store", "desktop-disks", "new-window-downloads",
    ]
    static let requiresFinderRestart: Set<String> = [
        "file-extensions", "hidden-files", "path-bar", "status-bar", "folders-first",
        "search-this-folder", "extension-warning", "path-in-title", "trash-30-days",
        "list-view", "desktop-disks", "new-window-downloads",
    ]

    static func downloads(home: URL) -> [Write] {
        [Write("com.apple.finder", "NewWindowTarget", .string("PfLo")),
         Write("com.apple.finder", "NewWindowTargetPath",
               .string(home.appendingPathComponent("Downloads", isDirectory: true).absoluteString))]
    }

    static func library(home: URL, hidden: Bool) -> TypingPreferencePlan.Command {
        .init(executable: "/bin/chflags", arguments: [hidden ? "hidden" : "nohidden",
                                                     home.appendingPathComponent("Library").path])
    }
}
