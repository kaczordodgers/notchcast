# Remote Mac integration

Remote Mac is the parent switch for SSH commands. Send to Remote Mac and Update Remote Mac
have independent switches, all off by default. Disabling the parent stops both modules and
gates their launcher commands. File transfers clean up their temporary remote staging directory.
The Finder Service remains deferred; the launcher command reads Finder's selected files.

The host, terminal directory, update script, backup status file and AI usage cache directory
are plain Settings fields, empty by default. Missing configuration reports a notice without
starting the operation. SSH callers share one address validator, including colon support.

`MachRemoteShell` adapts both worker protocols to `MachSSH`. SSH commands use its common
options and configured address; rsync uses those same options for its remote shell.
The current process adapter delivers output after process completion, so intermediate progress
does not stream to the island. No real update or transfer was performed during integration.

TLS MachLink remains independent of SSH. Shelf transfers resolve the paired endpoint per send;
the listener routes shelf requests before AI usage and acknowledges after persistence.
Backup status, link health and file-transfer notices use the existing island status messages.

Harnesses use synthetic data and fake runners. Live checks between Macs remain manual.
