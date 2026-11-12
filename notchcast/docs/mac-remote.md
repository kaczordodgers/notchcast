# Remote Mac integration

Remote Mac is the parent switch for SSH commands. Send to Remote Mac and Update Remote Mac
have independent switches, all off by default. Disabling the parent stops both modules and
gates their launcher commands. File transfers clean up their temporary remote staging directory.
The Finder Service remains deferred; the launcher command reads Finder's selected files.

The host, terminal directory, update script and backup status file are plain Settings fields, empty by default. AI usage reads the separate Magpie gateway setting, which defaults to loopback HTTP; it no longer reads a cache directory. Missing SSH configuration reports a notice without starting the operation. SSH callers share one address validator, including colon support.

`MachRemoteShell` adapts both worker protocols to `MachSSH`. An SSH command keeps the options its caller passed, followed by the common options and the configured address; rsync's remote shell keeps the caller's options the same way. ssh uses the first value it is given for an option, so a caller's `ConnectTimeout` wins over the common one. The current process adapter delivers output after process completion, so intermediate progress does not stream to the island. No real update or transfer was performed during integration.

TLS MachLink remains independent of SSH. Shelf transfers resolve the paired endpoint per send;
the listener routes shelf requests before AI usage and acknowledges after persistence.
Backup status, link health and file-transfer notices use the existing island status messages.

Harnesses use synthetic data and fake runners. Live checks between Macs remain manual.
