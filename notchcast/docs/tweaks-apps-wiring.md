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

Not wired: Apple app Dock filtering and Music launch-service disabling. Their
engine plans exist, but the current scalar preference reader cannot capture Dock
arrays, and the Music service has no reader for its existing disabled state.
Wiring these requires state capture that preserves the user's original values.
Additional Dock preset choices beyond the nine requested toggles are also omitted.

Validation uses fake runners only. No system preference changes, process restarts,
profile installations or launch-service changes are performed by the harnesses.
