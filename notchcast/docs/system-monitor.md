# System monitor engine

`MonitorStore.start()` enables the engine. A page retains a token from `beginDemand()` while
visible, then releases it or calls its idempotent `cancel()`. The store samples immediately and
every two seconds while at least one token remains. Monitor Alerts retains its own token at the
existing two-second cadence. `stop()` suspends sampling even if tokens remain; restarting resumes
their demand. Late samples from cancelled workers are discarded.

`startSpeedTest()` explicitly starts one download phase and one upload phase through
`SpeedTestRunner` and `/usr/bin/networkQuality`. `speedTestState` exposes the active phase,
cancellation and terminal outcomes. Cancellation retains the task until its runner unwinds, so
a replacement cannot overlap it. The ten newest successful results are session-only, newest first.
Stopping the store cancels the test. Tests inject a fake phase runner and never measure the network.

`requestPublicIP()` explicitly starts a lookup through `NetworkPublicIPService`; sampling and
startup never request it. Concurrent requests share the pending operation. Successful addresses
remain cached for the store's lifetime, including stop/start; failed lookups can be retried.
Stopping cancels the lookup and invalidates its identity before a later request can start.

Battery temperature alerts breach above 40 °C and recover at 35 °C by default, retaining the
existing three-sample sustain and fifteen-minute cooldown. The fork-local preference and Settings
row adjust the threshold with five degrees of recovery hysteresis. Its eight translations live
in `Monitor.xcstrings` for alerts and `Localizable.xcstrings` for Settings, whose standalone
harnesses do not depend on the monitor engine.

`quitProcess(_:force:service:)` takes the sampled process identity, including its start time.
`MonitorProcessService` reuses SystemTools' `KillProcessService` ownership, protection and identity
checks, then requests `NSRunningApplication.terminate()` or `forceTerminate()`. It returns a typed
outcome and refuses its own PID, other users, missing applications and reused PIDs. Confirmation
belongs to the future page's coordinator. Harnesses inject fake process entries and applications.
