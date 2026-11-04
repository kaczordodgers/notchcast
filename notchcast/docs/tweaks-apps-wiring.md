# Typing and app preference wiring

Five independent Notchcast switches default off: Typing, Finder, Dock and Windows,
Apple Apps and iPhone Backup. They do not depend on the island.
`NotchcastSettingsView` includes `NotchcastTweaksAppsSettingsRows()` in its Tweaks section.

Preference changes confirm first, capture the prior values and persist a rollback
journal in the bundle-specific Notchcast defaults suite before running commands.
Turning a group off confirms restoration. Restart-requiring rows disclose the
restart and restart only after the confirmed apply action. Restoration does not
restart processes. A failed operation retains its journal for a later retry.

Library visibility captures its previous hidden flag. Configuration profiles are
handed to macOS for approval; each restriction has a distinct profile identifier.
Installed profiles must be removed in System Settings, independently of the switch.
The backup folder action reveals the folder without changing backup contents.

Apple app Dock filtering captures the full persistent-apps array before writing.
Its receipt lives in the bundle-specific Notchcast defaults suite and survives relaunch.
Turning Apple Apps off restores removed tiles while preserving user additions.
Re-added apps are recognized by bundle identifier even when their tile GUID changes.
Apple app Dock writes synchronize preferences and restart the Dock on apply and restore;
restart failures are reported and retain the recovery receipt for a later restore.
An unreadable receipt blocks writes rather than replacing recovery data.
Music launch-service disabling remains unavailable: no reliable exact prior-state
capture and restoration exists for both the disabled override and booted-out job.
Additional Dock preset choices beyond the nine requested toggles are also omitted.

Validation uses fake runners only. No system preference changes, process restarts,
profile installations or launch-service changes are performed by the harnesses.
