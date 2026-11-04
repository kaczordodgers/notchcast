# Custom appearance

Settings → Notchcast → Appearance owns the custom appearance switch, upstream surface style,
light and dark theme slots, backdrop opacity and theme-link import. The switch defaults to on.
Turning it off restores upstream glass and colours without deleting the saved choices, disables
the dependent rows and hides the Theme command. It does not depend on the island switch.

Glass is the default surface. Empty theme slots retain upstream colours, including their original
dark and light token alphas. Surface styles affect upstream surfaces; this feature does not style
or own the island. General → Appearance still chooses which light or dark slot applies.

The Theme command opens a native palette list of bundled and imported themes. Settings opens a
native sheet for each slot. Highlighting or hovering previews without saving. Leaving the surface
or disabling the feature restores the window's previous appearance and ends its preview. Preview
owners prevent an old surface's dismissal from ending a newer surface's preview.

`raycast://theme` and the current channel's own `theme` URL go through the native import dialog.
Use Theme saves and selects; Just Add saves to the library; Cancel changes nothing. An external
`apply=1` parameter never skips the dialog. Invalid links report a failure. Corrupt saved theme
values reset once and report through the HUD.

`AppCore` owns `AppearanceCoordinator`, which owns `AppearanceStore`. `NotchcastCore` starts and
stops it through the appearance module entry. Preferences remain in the bundle-specific fork suite.
`AppearanceThemeColors` resolves the lock-protected palette for the upstream ramp, selection,
frosted controls, menus and palette backdrop.

The appearance harnesses cover parsing, persistence, colour resolution, switch restoration,
preview ownership, dialog dispatch and stale replies. Upstream harnesses compiling `Theme.swift`
declare appearance dependencies with `notchcast-sources` headers. The fork harness loader appends
these to an existing upstream registration; a new fork harness's headers declare its full sources.
