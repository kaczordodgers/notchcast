# Island ⇄ launcher states

Two owners: upstream's `PaletteWindowController` (launcher visible / key, `previousApp`, `previousOwnWindow`) and the fork's `IslandController` (`isOpen`, `isPinned`) with one `IslandPanel` per display (`open`, `launcherFrame`, `shownOutline`). They meet in `IslandController+Closed.swift` (`watchLauncher`, `restoreAfterLauncher`, `launcherDidShow`) and in two upstream lines in `PaletteWindowController` (`resolveAnchor` asks `NotchcastLauncherPlacement.anchor`; `show()` never records an island as the own window to refocus).

## Panel states

| State | `open` | `launcherFrame` | Surface | Takes key | Pointer |
|---|---|---|---|---|---|
| Closed | false | nil | closed outline | no | island shape |
| Open | true | nil | open outline | yes | island shape |
| Growing | false | set | morph closed → launcher | no | ignored |
| Hidden | false | set | launcher outline, opacity 0, out of the accessibility tree | no | ignored |

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
| Closed | launcher key | `NotchcastLauncherPlacement.island(hosting:among:)` is this panel | Growing | spring to the launcher; a CA-delayed dissolve starts at `Opening.dissolveDelay` (95% of the spring) |
| Growing | dissolve ends | — | Hidden | none: Core Animation finishes it, no timer runs; the surface left the accessibility tree when the dissolve began (`setVisible`) |
| Growing / Hidden | launcher gone | — | Closed | still visible: shrink back from the shape on screen; dissolved: reset unseen; fade back in `Opening.returnFade` |
| Growing / Hidden | island open | launcher already gone | Open | restore, then morph open |
| Closed | island open | — | Open | morph; key unless hover |
| Open | island dismiss | pin allows | Closed | morph; key handed back by re-ordering |

Placement and the grow share one predicate: placement on, the island visible and on the active space, on the launcher's display. A full-screen space without the island (Full Screen off) places the launcher at its own spot and nothing hides.

Same-outline re-presents (activity ticks) keep the running spring and fade (`IslandSurfaceView.present`); panels order front only when hidden or when their Spaces behaviour changes.
