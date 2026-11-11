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

# The backup schema collects every feature's own key file, written in the hub's BackupKeys vocabulary.
if [[ " $* " == *" Tinycast/Features/SettingsBackup/Model/ForkSettingsBackupSchema.swift "* ]]; then
    for source in Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift \
        $(find Tinycast/Features -mindepth 2 -name '*BackupKeys.swift' -not -path 'Tinycast/Features/Notchcast/Core/*' | sort); do
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

# Shared fork helpers no header lists: a compiled Tinycast source naming `<symbol>` brings its files in.
symbol_sources=(
    'ProcessRunner Tinycast/Features/Notchcast/Process/ProcessRunner.swift Tinycast/Platform/ProcessExit.swift'
    'WebRules Tinycast/Features/Notchcast/Model/WebRules.swift'
    'NotchcastIdentity Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift Tinycast/Platform/AppPaths.swift'
)
# Last, so it sees every source above; compgen expands globs even under the resolver's set -f.
symbol_readers=$(for source in "$@"; do [[ $source == Tinycast/*.swift ]] && compgen -G "$source"; done | tr '\n' ' '; true)
for symbol_row in "${symbol_sources[@]}"; do
    grep -lqsw "${symbol_row%% *}" $symbol_readers /dev/null || continue
    for source in ${symbol_row#* }; do
        declared=${source##*/}
        # A harness that declares the file's type itself keeps its stub.
        [[ " $symbol_readers " == *" $source "* ]] ||
            grep -qswE "^([a-z]+ )*(enum|struct|class|actor) ${declared%.swift}" "Tests/$name.swift" ||
            { set -- "$@" "$source"; symbol_readers+=" $source"; }
    done
done
