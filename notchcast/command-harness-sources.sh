case "$name" in
    app-installation-test|launcher-settings-file-test)
        set -- "$@" Tests/NotchcastCommandHarnessSupport.swift ;;
    hotkey-dispatch-test)
        set -- "$@" Tests/NotchcastHotKeyHarnessSupport.swift ;;
esac
