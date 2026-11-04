# System tools wiring

SystemTools and Tweaks register with the Notchcast module controller. Each folder runs while
any of its feature switches is on. Settings changes pass through SystemToolsStore; guarded
helper changes finish before the switch is persisted, including reversal on switch-off.

Startup Items lists user and system LaunchAgents. Only user agents are editable. Each change
asks through AppCore's confirmation dialog and rechecks the item before executing its engine
commands. System entries remain read-only. Runtime state comes from launchctl reads, rather
than guessing from plist contents.

SystemToolsProcessRunner accepts fixed absolute executables, passes arguments without a shell,
and bounds child execution with a timeout and cancellation. Blocking process work runs outside
the main actor. Helper operations use RootHelperClient and remain unavailable until their verbs
exist in RootContract.

The Accessibility notification observer, preset Apply/Undo controls, AI feature selectors and
privacy selectors are deferred. This wiring adds no automatic preference writes or AX actions.
Local harnesses use fake effects; they never apply changes to the host.
