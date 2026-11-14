# Remote Mac integration

Remote Mac is the parent switch for SSH commands. Send to Remote Mac and Update Remote Mac
have independent switches, all off by default. Disabling the parent stops both modules and
gates their launcher commands. File transfers clean up their temporary remote staging directory.
The Finder Service remains deferred; the launcher command reads Finder's selected files.

The host, terminal directory, update script and backup status file are plain Settings fields, empty by default. AI usage reads the separate Magpie gateway setting, which defaults to loopback HTTP; it no longer reads a cache directory. Missing SSH configuration reports a notice without starting the operation. SSH callers share one address validator, including colon support.

`MachRemoteShell` implements the single `RemoteShellRunning` protocol with typed SSH command/options and rsync source/destination entry points backed by `MachSSH`. An SSH command keeps the options its caller passed, followed by the common options and the configured address. Rsync takes no caller options and uses the common SSH options for its remote shell. ssh uses the first value it is given for an option, so an SSH caller's `ConnectTimeout` wins over the common one. Both entry points stream stdout while the process runs: the runner splits it into records at `\n` or `\r` (rsync `--progress` ends each update with `\r`), and the shell delivers each record, in order and once, with a trailing `\n` on the main actor before the call returns its unchanged final result. Send Files updates its percent and Update Remote its step and island lines as records arrive; cancelling the caller's task still stops the child. `Tests/nc-MachRemote-progress-test.swift` proves this with real blocking child processes. No real update or transfer was performed during integration.

TLS MachLink remains independent of SSH. Shelf transfers resolve the paired endpoint per send;
the listener routes shelf requests before AI usage and acknowledges after persistence.
Backup status, link health and file-transfer notices use the existing island status messages.

Harnesses use synthetic data and fake runners. Live checks between Macs remain manual.
