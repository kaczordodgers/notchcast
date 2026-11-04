case "$name" in
    app-installation-test|launcher-settings-file-test)
        set -- "$@" Tests/NotchcastCommandHarnessSupport.swift ;;
    hotkey-dispatch-test)
        set -- "$@" Tests/NotchcastHotKeyHarnessSupport.swift ;;
    notes-editor-test|notes-editor-performance)
        set -- "$@" Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift Tinycast/Features/Notchcast/Core/NotchcastFeature.swift ;;
esac
