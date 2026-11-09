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

# The hub's list names every descriptor file, at any depth, found as land.sh finds them.
if [[ " $* " == *" Tinycast/Features/Notchcast/Core/NotchcastFeature"* ]]; then
    for source in Tinycast/Features/Notchcast/Core/NotchcastFeature+Descriptor.swift \
        $(find Tinycast/Features -mindepth 2 -name '*Descriptor.swift' -not -path 'Tinycast/Features/Notchcast/Core/*' | sort); do
        [[ " $* " == *" $source "* ]] || set -- "$@" "$source"
    done
fi

# Fork code that runs a program goes through ProcessRunner, which needs ProcessExit; no harness header lists either.
runner_callers=$(for source in "$@"; do [[ $source == Tinycast/*.swift ]] && compgen -G "$source"; done | tr '\n' ' '; true)
if [[ " $runner_callers " != *" Tinycast/Features/Notchcast/Process/ProcessRunner.swift "* ]] &&
    grep -lqsE '(^|[^A-Za-z0-9_])ProcessRunner\.' $runner_callers /dev/null; then
    set -- "$@" Tinycast/Features/Notchcast/Process/ProcessRunner.swift
    [[ " $runner_callers " == *" Tinycast/Platform/ProcessExit.swift "* ]] || set -- "$@" Tinycast/Platform/ProcessExit.swift
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
