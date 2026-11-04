case "$name" in
    nc-Todo-store-test)
        set -- "$@" Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift ;;
    app-installation-test|launcher-settings-file-test)
        set -- "$@" Tests/NotchcastCommandHarnessSupport.swift ;;
    hotkey-dispatch-test)
        set -- "$@" Tests/NotchcastHotKeyHarnessSupport.swift ;;
esac
