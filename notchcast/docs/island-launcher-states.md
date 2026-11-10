# Island ⇄ launcher states

Two owners: upstream's `PaletteWindowController` (launcher visible / key, `previousApp`, `previousOwnWindow`) and the fork's `IslandController` (`isOpen`, `isPinned`) with one `IslandPanel` per display (`open`, `launcherFrame`, `shownOutline`). They meet in `IslandController+Closed.swift` (`watchLauncher`, `restoreAfterLauncher`, `launcherDidShow`) and in two upstream lines in `PaletteWindowController` (`resolveAnchor` asks `NotchcastLauncherPlacement.anchor`; `show()` never records an island as the own window to refocus).

## Panel states

| State | `open` | `launcherFrame` | Surface | Takes key | Pointer |
|---|---|---|---|---|---|
| Closed | false | nil | closed outline | no | island shape |
| Open | true | nil | open outline | yes | island shape |

`launcherFrame` is never set by the app since the launcher became its own glass panel under the island: `Growing` and `Hidden` (the black grown into the launcher's frame, then dissolved) are retired. Nothing calls `growIntoLauncher` any more, so `restoreAfterLauncher` and `launcherDidClose` still run on the events below and find nothing to restore.

## Events

| Event | Source |
|---|---|
| Launcher key | `NSWindow.didBecomeKeyNotification` with a `PalettePanel` key |
| Launcher gone | `didChangeOcclusionStateNotification` (a turn late), or `IslandController.open` finding no visible palette |
| Island open | click, hover, VoiceOver press, Toggle Island or page command |
| Island dismiss | Esc, page key, outside click, app switch, mouse-out |
| Display / space / preference | `rebuildPanels`, `updatePresenter`, `applyPreferences` |
| Interface size | `applyPreferences` → `IslandPanel.fitCanvas`: the canvas refits around the shape on screen, state kept |

## Transitions

| From | Event | Guard | To | Actions |
|---|---|---|---|---|
| Open | launcher key | `NotchcastLauncherPlacement.displaces`: hangs from it, or its open body covers or touches the launcher | Closed | `close()`, pin cleared: the launcher replaces the island |
| Open | launcher key | otherwise (placement off, launcher at its own spot, or on another display) | Open | none: pin kept, the launcher takes key |
| Closed | launcher key | any | Closed | none: the island stays as it is above the launcher hung under it |
| Closed | island open | not while the launcher is up: pointer hover and click are ignored | Open | morph; key unless hover |
| Open | island dismiss | pin allows | Closed | morph; key handed back by re-ordering |

Placement's predicate: placement on, the island visible and on the active space, on the launcher's display. A full-screen space without the island (Full Screen off) places the launcher at its own spot.

Same-outline re-presents (activity ticks) keep the running spring and fade (`IslandSurfaceView.present`); panels order front only when hidden or when their Spaces behaviour changes.
