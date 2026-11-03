# Root helper

M0 provides a fixed program and an app client. It has two argument-free verbs: `version` prints the
contract version (`1`) and `ping` prints `pong`. Both end with a newline. Any other argument vector
exits 64 without output or effects. Neither verb requires root when run directly. The program reads
no environment, launches no processes, and performs no system changes.

`RootContract.swift` here is a symlink to the app's contract under
`Tinycast/Features/Notchcast/Root/`, so both programs compile the same command table. There is no
helper Xcode target or resident daemon.

## Installation

Inspect `./notchcast/root/install.sh --dry-run` before running the script as root manually. It builds
with `swiftc -O`, installs `/Library/PrivilegedHelperTools/app.notchcast.root` as root:wheel 0755, and
grants the signed-in console user one NOPASSWD rule in `/etc/sudoers.d/notchcast`. The rule names only
the fixed helper path; the helper itself validates all arguments. The installer refuses unsafe
parent directories and symlink destinations and validates the rule with `visudo -cf` before moving
it into place. Re-running replaces the same helper and rule. `--uninstall` removes the rule first,
then the helper; it also accepts `--dry-run`.
The rule names the console user at install time; another user re-runs the installer.

## App contract

`RootHelperClient().run(.version)` returns `.version("1")`; `.run(.ping)` returns `.pong`. Calls use
`/usr/bin/sudo -n` with an empty environment, no stdin, and `/` as the working directory. Each call
checks every path component with `lstat`: root ownership, no group/world write permission, directory
parents, an executable regular file, and no symlinks. `isInstalled` reports that path check only;
sudo's authorization remains a separate typed failure at invocation.

Read operations time out after 3 seconds; the contract reserves 12 seconds for future changes. M0
exposes no change verbs. Cancellation and timeout terminate and reap the invocation. Replies must
match the command's complete expected output and version. Consumers own presentation of typed
failures; M0 adds no settings row or AppCore hook.

The `notchcast-root-client-test` harness covers parsing, replies, unsafe paths, permission policy,
timeout selection, process reaping and cancellation. Its processes are ordinary `/bin/sleep`
fixtures; it never invokes sudo or installs anything.
It also compiles the helper sources in a temporary directory and checks the executable's replies and exits.
