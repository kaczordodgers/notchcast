# Root helper

`spotlight-off` and `spotlight-on` run `/usr/bin/mdutil -a -i off` and
`/usr/bin/mdutil -a -i on` respectively, with an empty environment.
`sudo-touchid-on` adds `auth       sufficient     pam_tid.so` to `/etc/pam.d/sudo_local`;
`sudo-touchid-off` removes only that rule, preserving unrelated lines. Both validate the
`sudo_local` include in `/etc/pam.d/sudo`, reject unsupported PAM rules, and refuse symlink,
non-regular or non-root-owned local files. Writes use a temporary file in `/etc/pam.d`,
root:wheel ownership, mode 0444, fsync and atomic rename. These four argument-free change verbs
require root (exit 77 otherwise), return `ok` on success, and use the 12-second change timeout.
The harness verifies their unprivileged refusal and pure PAM transforms without changing the system.

The fixed program and app client share eleven argument-free verbs. `version` prints the contract version (`1`), and `ping` prints `pong`; neither requires root. Fan and battery verbs require root and print exactly `ok\n` on success. All replies end with a newline. Invalid argument vectors exit 64, unprivileged changes exit 77, and hardware failures exit 70, always without output. Only battery sleep verbs launch a process, with fixed arguments and an empty environment.

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

Read operations time out after 3 seconds; changes time out after 12 seconds. Cancellation and timeout terminate and reap the invocation. Replies must match the command's complete expected output and version. Consumers own presentation of typed failures; this helper adds no settings row or AppCore hook.

The `notchcast-root-client-test` harness covers parsing, replies, unsafe paths, permission policy,
timeout selection, process reaping and cancellation. Its processes are ordinary `/bin/sleep`
fixtures; it never invokes sudo or installs anything.
It also compiles the helper sources in a temporary directory and checks the executable's replies and exits.

## Battery operations

`BatterySMC.swift` reuses the helper's SMC connection. Before any write, every candidate key is probed,
present keys are read, and byte counts are validated. Missing keys are skipped; probe/read errors and
an empty plan fail without writing. All present keys are written, including on machines exposing both
generations. There is no macOS-version guess and no arbitrary key or command argument.

- `battery-charging-on`: `CHTE = [0,0,0,0]`, `CH0B = [0]`, `CH0C = [0]`, where present.
- `battery-charging-off`: `CHTE = [1,0,0,0]`, `CH0B = [2]`, `CH0C = [2]`, where present.
- `battery-adapter-on`: `CHIE = [0]`, `CH0I = [0]`, where present.
- `battery-adapter-off`: `CHIE = [8]`, `CH0I = [1]`, where present.
- `battery-sleep-on`: `/usr/bin/pmset -a disablesleep 0`.
- `battery-sleep-off`: `/usr/bin/pmset -a disablesleep 1`.

The harness checks SMC plans using fake access only and sleep arguments without invoking pmset.
Actual privileged operations require separate hardware validation.

## Fan implementation

`FanSMC.swift` is helper-only, adapted from Orion's SMC codec, connection and fan sequence. It is never compiled into the app. Fan count (`FNum`) must be integral and within 0–9; manual control requires at least one fan. Before manual writes, all fans' `F<n>Mn/Mx/Ac/Tg` readings, mode keys (`F<n>Md`, or `F<n>md` where exposed), target encodings and ranges are validated. Speeds must be finite and nonnegative; maximum must exceed minimum and stay within 20,000 RPM.

- `fans-auto`: write 0 to each fan's mode, then clear `Ftst` if present. Every release is attempted even if another fails. Targets are left alone.
- `fans-medium`: unlock `Ftst` with 1 if present and not already 1; for each fan, write mode 1 repeatedly every 100 ms until it reads back as 1, then write its target `min + 0.6 × (max − min)`.
- `fans-max`: the same unlock and mode sequence, targeting each fan's maximum instead.

All manual-mode retries share one five-second window. Any manual-operation failure attempts the complete Auto sequence before reporting failure. A failed key-info call is an error, not evidence that `Ftst` is absent. Numeric encodings follow the key's reported type (`flt ` little-endian, `fpe2` and unsigned integers big-endian); invalid sizes, unsupported types and overflow are rejected.

The harness compiles the shipped fan implementation with an in-memory SMC fixture to check targets, encoding bytes, retry timing, write order and failure recovery. Executable fan verbs run only without root and must fail before opening SMC. Live hardware verification and app lifecycle wiring are separate work.
