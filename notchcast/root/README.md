# Root helper

The fixed program and app client share five argument-free verbs. `version` prints the contract version (`1`), and `ping` prints `pong`; neither requires root. `fans-auto`, `fans-medium` and `fans-max` require root and print exactly `ok\n` on success. All replies end with a newline. Invalid argument vectors exit 64, unprivileged changes exit 77, and hardware failures exit 70, always without output. The program reads no environment and launches no processes.

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

Read operations time out after 3 seconds; fan changes time out after 12 seconds. Cancellation and timeout terminate and reap the invocation. Replies must match the command's complete expected output and version. Consumers own presentation of typed failures; this helper adds no settings row or AppCore hook.

The `notchcast-root-client-test` harness covers parsing, replies, unsafe paths, permission policy,
timeout selection, process reaping and cancellation. Its processes are ordinary `/bin/sleep`
fixtures; it never invokes sudo or installs anything.
It also compiles the helper sources in a temporary directory and checks the executable's replies and exits.

## Fan writes

`FanSMC.swift` is helper-only, adapted from Orion's SMC codec, connection and fan sequence. It is never compiled into the app. Fan count (`FNum`) must be integral and within 0–9; manual control requires at least one fan. Before manual writes, all fans' `F<n>Mn/Mx/Ac/Tg` readings, mode keys (`F<n>Md`, or `F<n>md` where exposed), target encodings and ranges are validated. Speeds must be finite and nonnegative; maximum must exceed minimum and stay within 20,000 RPM.

- `fans-auto`: write 0 to each fan's mode, then clear `Ftst` if present. Every release is attempted even if another fails. Targets are left alone.
- `fans-medium`: unlock `Ftst` with 1 if present and not already 1; for each fan, write mode 1 repeatedly every 100 ms until it reads back as 1, then write its target `min + 0.6 × (max − min)`.
- `fans-max`: the same unlock and mode sequence, targeting each fan's maximum instead.

All manual-mode retries share one five-second window. Any manual-operation failure attempts the complete Auto sequence before reporting failure. A failed key-info call is an error, not evidence that `Ftst` is absent. Numeric encodings follow the key's reported type (`flt ` little-endian, `fpe2` and unsigned integers big-endian); invalid sizes, unsupported types and overflow are rejected.

The harness compiles the shipped fan implementation with an in-memory SMC fixture to check targets, encoding bytes, retry timing, write order and failure recovery. Executable fan verbs run only without root and must fail before opening SMC. Live hardware verification and app lifecycle wiring are separate work.
