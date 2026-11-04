# Remote Mac fans

Enable Remote Mac and Remote Mac Fans in the Notchcast System settings, then run
Remote Mac Fans Auto, Remote Mac Fans 60%, or Remote Mac Fans Max in the launcher.
The fan switch defaults off and requires no island. The existing remote address setting
selects the destination; there are no additional settings.

Requests use MachSSH with its existing noninteractive options. The receiving Mac must
have the root helper installed with its sudo rule. Only the fixed helper path and the
existing fans-auto, fans-medium and fans-max verbs are sent. Medium targets 60% of each
fan's minimum-to-maximum range. The remote helper performs the SMC operation locally;
it never forwards a request to another Mac.

Failures produce a plain remote notice. A successful response must be exactly `ok`
followed by a newline. Disabling either switch cancels the owned task. Cancellation
cannot undo an operation already accepted by the remote helper; use Auto to restore
automatic control. Destination changes suppress stale results.

The remote fan harness uses an injected fake runner and never contacts a Mac or
changes fan settings. Hardware behavior and installation are separate live checks.
