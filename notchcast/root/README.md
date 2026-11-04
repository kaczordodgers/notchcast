# Root helper

## Caller authorization

Every verb except `version` and `ping` first authenticates its caller. Failure exits silently
with `RootContract.unauthorizedCallerExit` (78), before opening hardware or reading/changing policy.
The immediate parent must satisfy Apple's sudo code requirement. Its parent must satisfy
identifier `app.notchcast` and the leaf certificate SHA-1 from committed `notchcast/config.env`.
Installation verifies `/Applications/Notchcast.app` against that pin before baking it into the helper.
Security.framework checks dynamic code using kernel audit tokens obtained through task name ports;
parent relationships and process start times are rechecked to reject PID reuse during traversal.
The running app must have valid hardened runtime status, without get-task-allow or debugged status,
disabled library validation or DYLD environment entitlements. The source-tree helper has no pin
and cannot authorize protected verbs.

This blocks arbitrary user processes from using the NOPASSWD grant, including signed apps from
other certificates. It does not establish per-action user consent: compromised authorized app code,
an unsafe app command/deeplink, or another app signed with this identity can still invoke verbs.
Root and the signing authority remain trusted. Existing installations must reinstall the helper;
updating the app alone does not repair an old helper. Development/ad-hoc builds cannot use it.
Contract 3 identifies the caller-checked helper; versions 1 and 2 need reinstalling. Caller rejection
(exit 78) maps to `RootHelperClient.Failure.reinstallRequired` and the existing helper update hint.
The non-root harness checks its parent shell against Apple and Notchcast requirements and rejects
empty or missing pins, alongside injected identities and the live rejection path.

`charge-limit-60`, `charge-limit-70`, `charge-limit-80`, and `charge-limit-90` set
`mclLimitValue` and `MCLFeatureState = 1` in `com.apple.smartcharging.topoffprotection`
for root/current host, after pinning `HOME=/var/root` and removing `CFFIXED_USER_HOME`. They synchronize and post the Darwin notification
`com.apple.smartcharging.defaultschanged`; on AC, when MCL is disabled, they call PowerUI's
`enableMCL:`, then post the same notification without synchronizing again. `charge-limit-off` deletes both keys, synchronizes and notifies.
All five require root, take no arguments and return `ok\n` after confirming the preferences.
Adoption follows asynchronously; change verbs never invoke `pmset`. On battery they still check PowerUI support, but skip querying enabled state and enabling MCL. The preferences remain for powerd to adopt at plug-in; when MCL is off, this helper does not enable it at plug-in or confirm adoption. PowerUI calls and preference synchronization share a seven-second deadline, with restoration allowed until nine seconds, below the client's twelve-second timeout. Definite failures restore both prior preference values, synchronize and notify again. A timeout leaves the keys untouched and fails with the state unconfirmed, since an in-flight enable cannot be cancelled. There is no fallible step after successful enablement.
`charge-limit-read` needs no root and parses `/usr/bin/pmset -g battlimit`, returning a percentage
or `off`, followed by a newline, with the read timeout. Malformed or conflicting limits fail.
The harness checks fixed parser fixtures, transaction ordering and a simulated enablement timeout.
No privileged operation is exercised by these tests.

The MCL preferences and PowerUI mechanism is ported from Damian Tools' BatteryHelper,
which credits BatFi bbe0197, Copyright (c) 2023 Adam Różyński, under the MIT license.

`spotlight-off` and `spotlight-on` run `/usr/bin/mdutil -a -i off` and
`/usr/bin/mdutil -a -i on` respectively, with an empty environment.
`sudo-touchid-on` adds `auth       sufficient     pam_tid.so` to `/etc/pam.d/sudo_local`;
`sudo-touchid-off` removes only that rule, preserving unrelated lines. Both validate the
`sudo_local` include in `/etc/pam.d/sudo`, reject unsupported PAM rules, and refuse symlink,
non-regular or non-root-owned local files. Writes use a temporary file in `/etc/pam.d`,
root:wheel ownership, mode 0444, fsync and atomic rename. These four argument-free change verbs
require root (exit 77 otherwise) and return `ok` on success. Spotlight uses a 60-second timeout;
Touch ID uses the 12-second change timeout. Unchanged Touch ID content is never written.
The harness verifies pure PAM transforms without changing the system.

The fixed program and app client share twenty-five argument-free verbs. `version` prints the contract version (`3`), and `ping` prints `pong`; neither requires root, nor does `charge-limit-read`. Change verbs require root and print exactly `ok
` on success. All replies end with a newline. Invalid argument vectors exit 64, unprivileged changes exit 77, absent battery control keys exit 69, and other operation failures exit 70, without stdout. Charge-limit timeouts report unconfirmed state on stderr. Spotlight, battery sleep, standby and autopoweroff verbs launch processes, with fixed arguments and an empty environment.

`standby-off` and `standby-on` run `/usr/bin/pmset -a standby 0` and `/usr/bin/pmset -a standby 1`; `autopoweroff-off` and `autopoweroff-on` run `/usr/bin/pmset -a autopoweroff 0` and `/usr/bin/pmset -a autopoweroff 1`. These use the 12-second change timeout. The harness checks argument mappings without invoking pmset.

On the inspected MacBook Pro, `pmset -g cap` and `pmset -g custom` omit `autopoweroff`. The installed pmset binary still names the setting and its manual describes it for supported platforms, so the verbs remain available; their hardware effect on this Mac is unverified.

`RootContract.swift` here is a symlink to the app's contract under
`Tinycast/Features/Notchcast/Root/`, so both programs compile the same command table. There is no
helper Xcode target or resident daemon.

## Installation

Inspect `./notchcast/root/install.sh --dry-run` before running the script as root manually. It builds
with `swiftc -O`, installs `/Library/PrivilegedHelperTools/app.notchcast.root` as root:wheel 0755, and
grants the signed-in console user one NOPASSWD rule in `/etc/sudoers.d/notchcast`. The rule names only
the fixed helper path; the helper itself validates all arguments. The installer refuses unsafe
parent directories and symlink destinations and validates the rule with `visudo -cf` before moving
it into place. Installation removes the old rule and helper before pin lookup or verification;
any subsequent failure leaves the old grant revoked. Re-running replaces the helper and rule.
`--uninstall` removes the rule first,
then the helper; it also accepts `--dry-run`.
The rule names the console user at install time; another user re-runs the installer.

## App contract

`RootHelperClient().run(.version)` returns `.version("3")`; `.run(.ping)` returns `.pong`. Calls use
`/usr/bin/sudo -n` with an empty environment, no stdin, and `/` as the working directory. Each call
checks every path component with `lstat`: root ownership, no group/world write permission, directory
parents, an executable regular file, and no symlinks. `isInstalled` reports that path check only;
sudo's authorization remains a separate typed failure at invocation.

Read operations time out after 3 seconds; Spotlight changes after 60 seconds; other changes after 12 seconds. Cancellation and timeout terminate and reap the invocation. Replies must match the command's complete expected output and version. Consumers own presentation of typed failures; this helper adds no settings row or AppCore hook.

The `notchcast-root-client-test` harness covers parsing, replies, unsafe paths, permission policy,
timeout selection, process reaping and cancellation. Its processes are ordinary `/bin/sleep`
fixtures; it never invokes sudo or installs anything.
It also compiles the helper sources in a temporary directory, without launching the helper.

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

The harness compiles the shipped fan implementation with an in-memory SMC fixture to check targets, encoding bytes, retry timing, write order and failure recovery. Live hardware verification and app lifecycle wiring are separate work.
