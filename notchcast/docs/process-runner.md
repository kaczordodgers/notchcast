# Process supervision

`ProcessRunner.Request` names process-group cleanup explicitly: `keepAfterExit` preserves background jobs after a normal command exit, `killBeforeDrain` stops Download descendants before bounded output draining, and `drainThenKill` lets a caller finish consuming binary output before stopping descendants (no shipped caller since Archives was removed). Cancellation still stops the selected process or group and follows its signal ladder.

Quit supervision is opt-in through `killsOnQuit`; the shared runner owns the notification token for the lifetime of the job.

CommandRunner and Downloads build their environment through `ExecutableLocator.toolEnvironment(directories:home:inherited:)`; CommandRunner host commands also inherit `SSH_AUTH_SOCK` so agent-key `git` and `ssh` work; Downloads retains its filtered inherited values and locale. MachineBackup keeps its own PATH intentionally.

`Output.exitCode` applies the shell convention of 128 plus the signal number; `status` retains the raw exit status or signal number.
