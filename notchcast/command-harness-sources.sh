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

if [[ " $* " == *" Tinycast/Features/Settings/SettingsTab.swift "* ]]; then
    for source in Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift \
        Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettings*.swift \
        Tinycast/Features/Notchcast/Settings/Tree/NotchcastSetting.swift; do
        [[ " $* " == *" $source "* ]] || set -- "$@" "$source"
    done
fi
