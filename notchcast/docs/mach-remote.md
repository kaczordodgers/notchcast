# Remote Mac SSH

The Remote Mac switch defaults off and does not require the island. The address is a
fork-local preference, empty by default. An invalid or missing address reports a Settings notice.
Disabling the switch removes the
command from launcher availability and prevents command execution.

`MachSSH(address:runner:)` accepts an asynchronous injectable process runner.
`run(_:)` invokes `/usr/bin/ssh` with batch authentication, a five-second connection
timeout and five-second keep-alives (three missed responses). The caller owns the
task and its cancellation. The system runner terminates its child on cancellation.

`route(thunderboltAddress:)` reads `ssh -G` only on request. Callers inject the local
bridge address; no private network address is compiled into the app. Invalid output
or an SSH failure throws rather than claiming a route. This client is independent
of the TLS MachLink transport.

Open Remote Mac Terminal opens Terminal with an interactive SSH session in the
configured remote workspace. Exit 255 prints the localized reachability
message. A local login shell remains after SSH exits. There is no polling.

Harnesses use synthetic SSH configuration output and fake runners exclusively.
Terminal automation permission, a real connection and the installed appearance
remain morning checks.
