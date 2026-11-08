case "$name" in
    app-installation-test|launcher-settings-file-test)
        set -- "$@" Tests/NotchcastCommandHarnessSupport.swift ;;
    hotkey-dispatch-test)
        set -- "$@" Tests/NotchcastHotKeyHarnessSupport.swift ;;
    settings-history-test)
        set -- "$@" Tinycast/Features/Notchcast/Settings/NotchcastSettingsSearch.swift ;;
esac

if [[ " $* " == *" Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift "* ]]; then
    for source in Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift \
        Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift; do
        [[ " $* " == *" $source "* ]] || set -- "$@" "$source"
    done
fi

# Hidden-feature gates sit in upstream files any harness may compile; the core file has no dependencies.
if [[ " $* " == *" Tinycast/"* && " $* " != *" Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift "* ]]; then
    set -- "$@" Tinycast/Features/Notchcast/Hidden/NotchcastHidden.swift
fi

# Fork identity (suite, paths, subsystem, session) is read by fork files any harness may compile.
if [[ " $* " == *" Tinycast/"* ]]; then
    for source in Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift Tinycast/Platform/AppPaths.swift; do
        [[ " $* " == *" $source "* ]] || set -- "$@" "$source"
    done
fi

if [[ " $* " == *" Tinycast/Features/Settings/SettingsTab.swift "* ]]; then
    for source in Tinycast/Features/Notchcast/Hidden/NotchcastHidden+Tabs.swift \
        Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift \
        Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettings*.swift \
        Tinycast/Features/Notchcast/Settings/Tree/NotchcastSetting.swift; do
        [[ " $* " == *" $source "* ]] || set -- "$@" "$source"
    done
fi
