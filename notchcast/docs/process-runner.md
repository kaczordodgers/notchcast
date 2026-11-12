# Process supervision

`ProcessRunner.Request` names process-group cleanup explicitly: `keepAfterExit` preserves background jobs after a normal command exit, `killBeforeDrain` stops Download descendants before bounded output draining, and `drainThenKill` lets Archives finish consuming binary output before stopping descendants. Cancellation still stops the selected process or group and follows its signal ladder.

Quit supervision is opt-in through `killsOnQuit`; the shared runner owns the notification token for the lifetime of the job. Archives instead drains its active operations through its module's `beforeMacUpdate` termination hook.

Feature launch boundaries build their environment through `ExecutableLocator.environment(running:adding:inherited:)`. Downloads retains its filtered inherited values and locale; MachineBackup retains its isolated inherited environment.
