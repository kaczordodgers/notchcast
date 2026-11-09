#!/bin/bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 077

helper=/Library/PrivilegedHelperTools/app.notchcast.root
rule=/etc/sudoers.d/notchcast
dry_run=0
uninstall=0

for argument in "$@"; do
    case "$argument" in
        --dry-run) dry_run=1 ;;
        --uninstall) uninstall=1 ;;
        *) printf 'Usage: %s [--dry-run] [--uninstall]\n' "$0" >&2; exit 64 ;;
    esac
done

step() {
    if [ "$dry_run" -eq 1 ]; then
        printf 'Would run:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

if [ "$dry_run" -eq 0 ] && [ "$(/usr/bin/id -u)" -ne 0 ]; then
    printf 'Installation and removal require root. Use --dry-run to inspect the steps.\n' >&2
    exit 77
fi

if [ "$uninstall" -eq 1 ]; then
    step /bin/rm -f "$rule"
    step /bin/rm -f "$helper"
    exit 0
fi

step /bin/rm -f "$rule"
step /bin/rm -f "$helper"

console_user=$(/usr/bin/stat -f '%Su' /dev/console)
if [[ ! "$console_user" =~ ^[a-z_][a-z0-9_.-]{0,30}$ ]] || [ "$console_user" = root ]; then
    printf 'A signed-in console user with a plain account name is required.\n' >&2
    exit 65
fi

source_directory=$(cd "$(/usr/bin/dirname "$0")" && pwd)
# Root compiles these sources: refuse uncommitted edits and show the commit they come from.
app_sources=(../../Tinycast/Features/Clean/Model/CleanSystemEntry.swift ../../Tinycast/Features/Clean/Model/CleanSystemPlan.swift ../../Tinycast/Features/Clean/Model/CleanSystemPolicy.swift ../../Tinycast/Features/SystemTools/Model/TouchIDPolicy.swift ../../Tinycast/Features/SystemMonitor/Model/SMCValue.swift ../../Tinycast/Features/Notchcast/Root/RootContract.swift)
if [ -n "$(/usr/bin/git -C "$source_directory" status --porcelain -- . "${app_sources[@]}")" ]; then
    printf 'Helper sources have uncommitted changes; commit or discard them first.\n' >&2
    exit 65
fi
printf 'Installing the helper from commit %s.\n' "$(/usr/bin/git -C "$source_directory" rev-parse HEAD)"
app=/Applications/Notchcast.app
leaf_sha1=$(/usr/bin/git -C "$source_directory" show HEAD:notchcast/config.env | /usr/bin/sed -n 's/^SIGN_SHA1=//p')
if [[ ! "$leaf_sha1" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    printf 'A committed signing certificate pin is required.\n' >&2
    exit 65
fi
step /usr/bin/codesign --verify --strict -R "identifier app.notchcast and certificate leaf = H\"$leaf_sha1\"" "$app"
if [ "$dry_run" -eq 1 ]; then
    stage='<private temporary directory>'
    step /usr/bin/mktemp -d /private/tmp/notchcast-root.XXXXXX
else
    stage=$(/usr/bin/mktemp -d /private/tmp/notchcast-root.XXXXXX)
    trap '/bin/rm -rf "$stage"' EXIT
fi

step /bin/cp "$source_directory/NativeChargeLimit.swift" "$source_directory/../../Tinycast/Features/Notchcast/Root/RootContract.swift" "$source_directory/main.swift" "$source_directory/FanSMC.swift" "$source_directory/BatterySMC.swift" "$source_directory/Spotlight.swift" "$source_directory/SudoTouchID.swift" "$source_directory/../../Tinycast/Features/SystemTools/Model/TouchIDPolicy.swift" "$source_directory/Power.swift" "$stage/"
step /usr/bin/shasum -a 256 "$stage/NativeChargeLimit.swift" "$stage/RootContract.swift" "$stage/main.swift" "$stage/FanSMC.swift" "$stage/BatterySMC.swift" "$stage/Spotlight.swift" "$stage/SudoTouchID.swift" "$stage/TouchIDPolicy.swift" "$stage/Power.swift"
step /bin/cp "$source_directory/../../Tinycast/Features/SystemMonitor/Model/SMCValue.swift" "$stage/"
step /usr/bin/shasum -a 256 "$stage/SMCValue.swift"
step /bin/cp "$source_directory/RootCaller.swift" "$stage/RootCaller.swift"
step /bin/cp "$source_directory/CleanSystem.swift" "$source_directory/../../Tinycast/Features/Clean/Model/CleanSystemEntry.swift" "$source_directory/../../Tinycast/Features/Clean/Model/CleanSystemPlan.swift" "$source_directory/../../Tinycast/Features/Clean/Model/CleanSystemPolicy.swift" "$stage/"
step /usr/bin/shasum -a 256 "$stage/RootCaller.swift" "$stage/CleanSystem.swift" "$stage/CleanSystemEntry.swift" "$stage/CleanSystemPlan.swift" "$stage/CleanSystemPolicy.swift"
if [ "$dry_run" -eq 1 ]; then
    printf 'Would generate CallerRequirement.swift with committed leaf SHA-1 %s.\n' "$leaf_sha1"
else
    printf 'enum CallerRequirement { static let leafSHA1 = "%s" }\n' "$leaf_sha1" > "$stage/CallerRequirement.swift"
fi
step /usr/bin/shasum -a 256 "$stage/CallerRequirement.swift"
step /usr/bin/xcrun swiftc -swift-version 6 -O "$stage/CallerRequirement.swift" "$stage/RootCaller.swift" "$stage/NativeChargeLimit.swift" "$stage/RootContract.swift" \
    "$stage/main.swift" "$stage/FanSMC.swift" "$stage/SMCValue.swift" "$stage/BatterySMC.swift" "$stage/Spotlight.swift" "$stage/SudoTouchID.swift" "$stage/TouchIDPolicy.swift" "$stage/Power.swift" "$stage/CleanSystem.swift" "$stage/CleanSystemEntry.swift" "$stage/CleanSystemPlan.swift" "$stage/CleanSystemPolicy.swift" -o "$stage/helper"
if [ "$dry_run" -eq 1 ]; then
    printf 'Would write %s with exactly one rule:\n' "$stage/notchcast"
    printf '%s ALL=(root) NOPASSWD: %s\n' "$console_user" "$helper"
else
    printf '%s ALL=(root) NOPASSWD: %s\n' "$console_user" "$helper" > "$stage/notchcast"
fi
step /usr/sbin/visudo -cf "$stage/notchcast"

for directory in /Library /Library/PrivilegedHelperTools /private /private/etc /private/etc/sudoers.d; do
    if [ -L "$directory" ]; then
        printf 'Refusing a symlink directory: %s\n' "$directory" >&2
        exit 65
    fi
    if [ -d "$directory" ]; then
        owner=$(/usr/bin/stat -f '%u' "$directory")
        permissions=$(/usr/bin/stat -f '%Lp' "$directory")
        if [ "$owner" -ne 0 ] || (( (8#$permissions & 0022) != 0 )); then
            printf 'Refusing an unsafe directory: %s\n' "$directory" >&2
            exit 65
        fi
    fi
done

for directory in /Library/PrivilegedHelperTools /private/etc/sudoers.d; do
    if [ ! -d "$directory" ]; then
        step /usr/bin/install -d -o root -g wheel -m 0755 "$directory"
    fi
done
for destination in "$helper" "$rule"; do
    if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -f "$destination" ]; }; then
        printf 'Refusing a non-regular destination: %s\n' "$destination" >&2
        exit 65
    fi
done
step /usr/bin/install -o root -g wheel -m 0755 "$stage/helper" "$helper"
if [ "$dry_run" -eq 1 ]; then
    staged_rule='/etc/sudoers.d/.notchcast.XXXXXX'
    step /usr/bin/mktemp "$staged_rule"
else
    staged_rule=$(/usr/bin/mktemp /etc/sudoers.d/.notchcast.XXXXXX)
    trap '/bin/rm -f "$staged_rule"; /bin/rm -rf "$stage"' EXIT
fi
step /usr/bin/install -o root -g wheel -m 0440 "$stage/notchcast" "$staged_rule"
step /usr/sbin/visudo -cf "$staged_rule"
step /bin/mv -f "$staged_rule" "$rule"
step /bin/rm -rf "$stage"
