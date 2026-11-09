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

if [[ " $* " == *" Tinycast/Features/Settings/SettingsTab.swift "* ]]; then
    for source in Tinycast/Features/Notchcast/Hidden/NotchcastHidden+Tabs.swift \
        Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift \
        Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettings*.swift \
        Tinycast/Features/Notchcast/Settings/Tree/NotchcastSetting.swift; do
        [[ " $* " == *" $source "* ]] || set -- "$@" "$source"
    done
fi

# The hub's descriptor list names every feature's own descriptor file, at any depth, as land.sh finds them.
if [[ " $* " == *" Tinycast/Features/Notchcast/Core/NotchcastFeature"* ]]; then
    for source in Tinycast/Features/Notchcast/Core/NotchcastFeature+Descriptor.swift \
        $(find Tinycast/Features -mindepth 2 -name '*Descriptor.swift' -not -path 'Tinycast/Features/Notchcast/Core/*' | sort); do
        [[ " $* " == *" $source "* ]] || set -- "$@" "$source"
    done
fi

# Last, so it sees every source above; compgen expands globs even under the resolver's set -f.
identity_readers=$(for source in "$@"; do [[ $source == Tinycast/*.swift ]] && compgen -G "$source"; done; true)
if [[ " $* " != *" Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift "* ]] &&
    grep -lqs NotchcastIdentity $identity_readers /dev/null; then
    set -- "$@" Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift
    # A harness that stubs AppPaths keeps its stub.
    [[ " $* " == *" Tinycast/Platform/AppPaths.swift "* ]] || grep -q '^enum AppPaths' "Tests/$name.swift" ||
        set -- "$@" Tinycast/Platform/AppPaths.swift
fi
