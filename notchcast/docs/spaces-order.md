# Fixed Spaces order

Settings › Notchcast offers an opt-in switch independent of the island. While enabled,
the module checks Dock's `mru-spaces` preference every 30 seconds and holds it false.
Dock restarts only after a preference change. No accessibility permission is required.

The original explicit true, explicit false, or absent value is saved in the app's
fork-local defaults before changing Dock. Turning off restores that value, including
removing a previously absent key. The backup survives app restarts; if the switch is
off at startup, any pending restoration runs then. Quitting leaves the hold's setting
in place, ready to resume at next launch.

Preference synchronization failures leave the backup intact and report through the HUD.
The pure engine is checked by `notchcast-spaces-order-test`.

This is an independent implementation of the catalogue's preference-hold behavior;
no third-party source code is included.
