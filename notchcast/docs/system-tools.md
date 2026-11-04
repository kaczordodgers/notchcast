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

The notification observer attaches to Notification Center only while cleanup is enabled and
Accessibility is granted. It rechecks both before each sweep and selects individual disk-ejection
alerts through NotificationCleanupPolicy. Currently recognized system titles are English and Polish.
Turning cleanup off detaches the observer; module teardown also invalidates its lifecycle timer.

TweakProfileRunner stages generated profiles in a bundle-scoped cache folder and hands them to
macOS using /usr/bin/open through an injected closure. This requests user approval; it does not
install a profile or prove approval. Local harnesses replace the closure and never apply changes
to the host.

Preset Apply/Undo controls and AI/privacy selectors remain deferred. MacSetupPlan receipts cover
preference changes only; the broader preset catalog also contains service, power, Dock and profile
actions that have no reversible runner in this wiring.
