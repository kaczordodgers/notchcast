import Foundation

nonisolated enum MacSetupPresetCatalog {
    enum Preset: String, Sendable { case full, recommended, privacy }
    enum Action: Sendable {
        case preferences([(TweakPreference, TweakValue)])
        case forced([(TweakPreference, TweakValue)])
        case restriction(String)
        case ai(String)
        case services(String)
        case power(String, Int)
        case command(TweakCommand)
        case dockRemove([String])
        case musicLaunchEntry
        case spotlightCategories([String])
        case unavailable(String)
    }
    struct Entry: Sendable {
        let id: String
        let group: String
        let presets: Set<Preset>
        let action: Action
    }

    static func entries(home: URL) -> [Entry] {
        [
            .init(id: "background-intelligence", group: "background",
                 presets: [.full], action: .services("intelligence")),
                
            .init(id: "background-knowledge", group: "background", presets: [.full], action: .services("knowledge")),
            .init(id: "background-photos", group: "background", presets: [.full], action: .services("photos")),
            .init(id: "background-spotlight", group: "background", presets: [.full], action: .services("spotlight")),
            .init(id: "lookup-disabled", group: "privacy", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.lookup.shared",
                 key: "LookupDisabled", value: .bool(true))])),
                
            .init(id: "spotlight-ui", group: "privacy", presets: [.full], action: .spotlightCategories([
                "APPLICATIONS", "MENU_EXPRESSION", "MENU_CONVERSION", "MENU_DEFINITION", "SYSTEM_PREFS",
                "DOCUMENTS", "DIRECTORIES", "PRESENTATIONS", "SPREADSHEETS", "PDF", "MESSAGES", "CONTACT",
                "EVENT_TODO", "IMAGES", "BOOKMARKS", "MUSIC", "MOVIES", "FONTS", "MENU_OTHER", "SOURCE",
                "MENU_WEBSEARCH", "MENU_SPOTLIGHT_SUGGESTIONS"])),
            .init(id: "ai-siri", group: "ai", presets: [.full], action: .ai("siri")),
            .init(id: "ai-chatgpt", group: "ai", presets: [.full], action: .ai("chatgpt")),
            .init(id: "ai-writing-tools", group: "ai", presets: [.full], action: .ai("writing-tools")),
            .init(id: "ai-genmoji", group: "ai", presets: [.full], action: .ai("genmoji")),
            .init(id: "ai-image-playground", group: "ai", presets: [.full], action: .ai("image-playground")),
            .init(id: "ai-mail", group: "ai", presets: [.full], action: .ai("mail")),
            .init(id: "ai-notification-summaries", group: "ai",
                 presets: [.full], action: .ai("notification-summaries")),
                
            .init(id: "ai-messages-summaries", group: "ai", presets: [.full], action: .ai("messages-summaries")),
            .init(id: "ai-safari-summaries", group: "ai", presets: [.full], action: .ai("safari-summaries")),
            .init(id: "ai-notes-summaries", group: "ai", presets: [.full], action: .ai("notes-summaries")),
            .init(id: "ai-inline-predictions", group: "ai", presets: [.full], action: .ai("inline-predictions")),
            .init(id: "ai-spatial-photos", group: "ai", presets: [.full], action: .ai("spatial-photos")),
            .init(id: "ai-photos-clean-up", group: "ai", presets: [.full], action: .ai("photos-clean-up")),
            .init(id: "ai-xcode-completion", group: "ai", presets: [.full], action: .ai("xcode-completion")),
            .init(id: "analytics", group: "privacy", presets: [.full,
                 .privacy, .recommended], action: .restriction("allowDiagnosticSubmission")),
                
            .init(id: "personalized-ads", group: "privacy", presets: [.full,
                 .privacy, .recommended], action: .restriction("allowApplePersonalizedAdvertising")),
                
            .init(id: "improve-siri", group: "privacy", presets: [.full,
                 .privacy, .recommended], action: .forced([setting(domain: "com.apple.assistant.support",
                 key: "Siri Data Sharing Opt-In Status", value: .integer(2))])),
                
            .init(id: "improve-search", group: "privacy", presets: [.full,
                 .privacy, .recommended], action: .forced([setting(domain: "com.apple.assistant.support",
                 key: "Search Queries Data Sharing Status", value: .integer(2))])),
                
            .init(id: "spotlight-web", group: "privacy", presets: [.full,
                 .privacy, .recommended], action: .restriction("allowSpotlightInternetResults")),
                
            .init(id: "lookup-suggestions", group: "privacy",
                 presets: [.full, .privacy, .recommended], action: .forced([setting(domain: "com.apple.lookup.shared",
                 key: "LookupSuggestionsDisabled", value: .bool(true))])),
                
            .init(id: "safari-suggestions", group: "privacy",
                 presets: [.full, .privacy], action: .forced([setting(domain: "com.apple.Safari",
                 key: "UniversalSearchEnabled", value: .bool(false)),
                 setting(domain: "com.apple.Safari", key: "SuppressSearchSuggestions",
                 value: .bool(true))])),
            .init(id: "game-center", group: "privacy", presets: [.full,
                 .privacy], action: .restriction("allowGameCenter")),
                
            .init(id: "click-to-desktop", group: "annoyances",
                 presets: [.full, .recommended], action: .preferences([setting(domain: "com.apple.WindowManager",
                 key: "EnableStandardClickToShowDesktop", value: .bool(false))])),
                
            .init(id: "desktop-widgets", group: "annoyances",
                 presets: [.full], action: .preferences([setting(domain: "com.apple.WindowManager",
                 key: "StandardHideWidgets", value: .bool(true)),
                 setting(domain: "com.apple.WindowManager", key: "StageManagerHideWidgets",
                 value: .bool(true))])),
            .init(id: "media-keys", group: "annoyances", presets: [], action: .services("media-keys")),
            .init(id: "music-launches", group: "annoyances", presets: [], action: .musicLaunchEntry),
            .init(id: "iphone-mirroring", group: "annoyances",
                 presets: [.full], action: .restriction("allowiPhoneMirroring")),
                
            .init(id: "music-classic", group: "apps", presets: [.full], action: .restriction("allowMusicService")),
            .init(id: "book-store", group: "apps", presets: [.full], action: .restriction("allowBookstore")),
            .init(id: "dock-apple-apps", group: "apps", presets: [.full], action: .dockRemove([
                "com.apple.news", "com.apple.TV", "com.apple.Music", "com.apple.podcasts", "com.apple.iBooksX",
                "com.apple.freeform", "com.apple.Maps", "com.apple.stocks",
                "com.apple.GenerativePlaygroundApp", "com.apple.journal"])),
            .init(id: "dock-autohide", group: "dock", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.dock",
                 key: "autohide", value: .bool(true))])),
            .init(id: "dock-delay", group: "dock", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.dock",
                 key: "autohide-delay", value: .real(0))])),
                
            .init(id: "dock-instant", group: "dock", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.dock",
                 key: "autohide-time-modifier", value: .integer(0))])),
                
            .init(id: "dock-left", group: "dock", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.dock",
                 key: "orientation", value: .string("left"))])),
                
            .init(id: "dock-recents", group: "dock", presets: [.full,
                 .recommended], action: .preferences([setting(domain: "com.apple.dock",
                 key: "show-recents", value: .bool(false))])),
                
            .init(id: "minimize-to-app", group: "dock", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.dock",
                 key: "minimize-to-application", value: .bool(true))])),
                
            .init(id: "dock-scale", group: "dock", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.dock",
                 key: "mineffect", value: .string("scale"))])),
                
            .init(id: "dock-bounce", group: "dock", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.dock",
                 key: "launchanim", value: .bool(false))])),
            .init(id: "dock-corner", group: "dock", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.dock",
                 key: "wvous-br-corner", value: .integer(1))])),
                
            .init(id: "group-windows", group: "windows", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.dock",
                 key: "expose-group-apps", value: .bool(true))])),
                
            .init(id: "window-animations", group: "windows", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "NSAutomaticWindowAnimationsEnabled", value: .bool(false))])),
                
            .init(id: "title-fill", group: "windows", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "AppleActionOnDoubleClick", value: .string("Fill"))])),
                
            .init(id: "stage-off", group: "windows", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.WindowManager",
                 key: "GloballyEnabled", value: .bool(false))])),
                
            .init(id: "tile-edge", group: "windows", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.WindowManager",
                 key: "EnableTilingByEdgeDrag", value: .bool(false))])),
                
            .init(id: "tile-top", group: "windows", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.WindowManager",
                 key: "EnableTopTilingByEdgeDrag", value: .bool(false))])),
                
            .init(id: "tile-margins", group: "windows", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.WindowManager",
                 key: "EnableTiledWindowMargins", value: .bool(false))])),
                
            .init(id: "hide-desktop", group: "windows", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.WindowManager",
                 key: "HideDesktop", value: .bool(true)), setting(domain: "com.apple.WindowManager",
                 key: "StandardHideDesktopIcons", value: .bool(true))])),
                
            .init(id: "menubar-hide", group: "menubar", presets: [],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "_HIHideMenuBar", value: .bool(true))])),
                
            .init(id: "dark", group: "menubar", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "AppleInterfaceStyle", value: .string("Dark"))])),
                
            .init(id: "clock-seconds", group: "menubar", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.menuextra.clock",
                 key: "ShowSeconds", value: .bool(true))])),
            .init(id: "scrollbars", group: "menubar", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "AppleShowScrollBars", value: .string("WhenScrolling"))])),
                
            .init(id: "tinting", group: "menubar", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "AppleReduceDesktopTinting", value: .bool(false))])),
                
            .init(id: "repeat-rate", group: "keyboard", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "KeyRepeat", value: .integer(2))])),
            .init(id: "repeat-delay", group: "keyboard", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "InitialKeyRepeat", value: .integer(15))])),
                
            .init(id: "key-repeat", group: "keyboard", presets: [],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "ApplePressAndHoldEnabled", value: .bool(false))])),
                
            .init(id: "smart-punctuation", group: "keyboard",
                 presets: [.full], action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "NSAutomaticQuoteSubstitutionEnabled", value: .bool(false)),
                 setting(domain: ".GlobalPreferences", key: "NSAutomaticDashSubstitutionEnabled",
                 value: .bool(false))])),
            .init(id: "double-space-period", group: "keyboard",
                 presets: [.full], action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "NSAutomaticPeriodSubstitutionEnabled",
                 value: .bool(false))])),
            .init(id: "autocorrect", group: "keyboard", presets: [],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "NSAutomaticSpellingCorrectionEnabled",
                 value: .bool(false))])),
            .init(id: "auto-capitalize", group: "keyboard", presets: [],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "NSAutomaticCapitalizationEnabled", value: .bool(false))])),
                
            .init(id: "tap-click", group: "trackpad", presets: [.full],
                 action: .preferences(trackpad("Clicking", .bool(true)) + [setting(domain: ".GlobalPreferences",
                 key: "com.apple.mouse.tapBehavior", value: .integer(1),
                 currentHost: true)])),
            .init(id: "secondary", group: "trackpad", presets: [.full],
                 action: .preferences(trackpad("TrackpadRightClick",
                 .bool(true)))),
            .init(id: "natural-off", group: "trackpad", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "com.apple.swipescrolldirection", value: .bool(false))])),
                
            .init(id: "tracking", group: "trackpad", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "com.apple.trackpad.scaling", value: .integer(2))])),
                
            .init(id: "click-pressure", group: "trackpad", presets: [.full],
                 action: .preferences(trackpad("FirstClickThreshold",
                 .integer(1)))),
            .init(id: "swipe-spaces", group: "trackpad", presets: [.full],
                 action: .preferences(trackpad("TrackpadThreeFingerHorizSwipeGesture",
                 .integer(2)))),
            .init(id: "lookup-tap", group: "trackpad", presets: [.full],
                 action: .preferences(trackpad("TrackpadThreeFingerTapGesture",
                 .integer(0)))),
            .init(id: "file-extensions", group: "finder", presets: [.full,
                 .privacy, .recommended], action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "AppleShowAllExtensions", value: .bool(true))])),
                
            .init(id: "extension-warning", group: "finder", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.finder",
                 key: "FXEnableExtensionChangeWarning", value: .bool(false))])),
                
            .init(id: "path-bar", group: "finder", presets: [.full,
                 .recommended], action: .preferences([setting(domain: "com.apple.finder",
                 key: "ShowPathbar", value: .bool(true))])),
            .init(id: "list-view", group: "finder", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.finder",
                 key: "FXPreferredViewStyle", value: .string("Nlsv"))])),
                
            .init(id: "search-this-folder", group: "finder", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.finder",
                 key: "FXDefaultSearchScope", value: .string("SCcf"))])),
                
            .init(id: "new-window-downloads", group: "finder",
                 presets: [.full], action: .preferences([setting(domain: "com.apple.finder",
                 key: "NewWindowTarget", value: .string("PfLo")),
                 setting(domain: "com.apple.finder", key: "NewWindowTargetPath",
                 value: .string(home.appendingPathComponent("Downloads",
                 isDirectory: true).absoluteString))])),
            .init(id: "folders-first", group: "finder", presets: [.full,
                 .recommended], action: .preferences([setting(domain: "com.apple.finder",
                 key: "_FXSortFoldersFirst", value: .bool(true))])),
                
            .init(id: "desktop-disks", group: "finder", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.finder",
                 key: "ShowHardDrivesOnDesktop", value: .bool(false)),
                 setting(domain: "com.apple.finder", key: "ShowExternalHardDrivesOnDesktop",
                 value: .bool(false)), setting(domain: "com.apple.finder",
                 key: "ShowRemovableMediaOnDesktop", value: .bool(false)),
                 setting(domain: "com.apple.finder", key: "ShowMountedServersOnDesktop",
                 value: .bool(false))])),
            .init(id: "trash-30-days", group: "finder", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.finder",
                 key: "FXRemoveOldTrashItems", value: .bool(true))])),
                
            .init(id: "network-ds-store", group: "finder", presets: [.full,
                 .recommended], action: .preferences([setting(domain: "com.apple.desktopservices",
                 key: "DSDontWriteNetworkStores", value: .bool(true))])),
                
            .init(id: "usb-ds-store", group: "finder", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.desktopservices",
                 key: "DSDontWriteUSBStores", value: .bool(true))])),
                
            .init(id: "expanded-save", group: "finder", presets: [.full],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "NSNavPanelExpandedStateForSaveMode", value: .bool(true))])),
                
            .init(id: "show-library", group: "finder", presets: [.full], action: .command(
                TweakCommand(executable: "/bin/chflags", arguments: ["nohidden",
                 home.appendingPathComponent("Library").path]))),
                
            .init(id: "hidden-files", group: "finder", presets: [],
                 action: .preferences([setting(domain: "com.apple.finder",
                 key: "AppleShowAllFiles", value: .bool(true))])),
                
            .init(id: "status-bar", group: "finder", presets: [],
                 action: .preferences([setting(domain: "com.apple.finder",
                 key: "ShowStatusBar", value: .bool(true))])),
                
            .init(id: "path-in-title", group: "finder", presets: [],
                 action: .preferences([setting(domain: "com.apple.finder",
                 key: "_FXShowPosixPathInTitle", value: .bool(true))])),
                
            .init(id: "screenshot-shadow", group: "capture", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.screencapture",
                 key: "disable-shadow", value: .bool(true))])),
                
            .init(id: "textedit-plain", group: "capture", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.TextEdit",
                 key: "RichText", value: .bool(false))])),
            .init(id: "optimize-off", group: "storage", presets: [.full],
                 action: .preferences([setting(domain: "com.apple.bird",
                 key: "optimize-storage", value: .bool(false))])),
                
            .init(id: "save-locally", group: "storage", presets: [],
                 action: .preferences([setting(domain: ".GlobalPreferences",
                 key: "NSDocumentSaveNewDocumentsToCloud", value: .bool(false))])),
                
            .init(id: "standby", group: "power", presets: [.full], action: .power("standby", 0)),
            .init(id: "autopoweroff", group: "power", presets: [.full], action: .power("autopoweroff", 0)),
            .init(id: "wallpaper-black", group: "menubar", presets: [.full], action: .unavailable("wallpaper-black"))
        ]
    }

    static func selection(_ preset: Preset, home: URL) -> [Entry] {
        let selected: Set<Preset> = preset == .privacy ? [.recommended, .privacy] : [preset]
        return entries(home: home).filter { !$0.presets.isDisjoint(with: selected) }
    }

    private static func setting(domain: String, key: String, value: TweakValue,
                                currentHost: Bool = false) -> (TweakPreference, TweakValue) {
        (.init(domain: domain, key: key, currentHost: currentHost), value)
    }

    private static func trackpad(_ key: String, _ value: TweakValue) -> [(TweakPreference, TweakValue)] {
        ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].map {
            setting(domain: $0, key: key, value: value)
        }
    }
}
