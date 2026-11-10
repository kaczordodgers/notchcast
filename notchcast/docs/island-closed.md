# Closed notch, closed island, opening into the launcher — rule sheet

One design, two shapes. Every value lives in `Tinycast/Features/Notchcast/Island/NotchcastTheme.swift` (`Closed`, `Value`, `Visualizer`, `Opening` groups) or comes straight from Tinycast's `Theme`. Sources: **T** = Tinycast code (`Theme.swift` line), **L** = measured on the launcher (`refs/1-tinycast-launcher.png`, 2× capture, 750 pt panel = 1500 px), **D** = Damian's words in `look-decisions.md`, **O** = Orion (shape/music layout/visualizer, named by D), **DT** = Damian Tools visualizer, **★** = my taste call (reason given).

## Measured launcher (the yardstick)
| What | Value | Source |
|---|---|---|
| Panel | 750 × 475, radius 26 continuous, compact 56 capsule | T `Size.panelWidth/Height`, `Radius.panel`, `Size.compactHeight`; L 1500 px wide |
| Row | 26 icon, 10 icon→title, 8/6 insets, pitch 38, radius 10 | T `resultRowIcon`, `Spacing.lg/md/sm`, `Radius.row`; L rows 65 px apart |
| Type | title `.body` 13, trailing `.callout` 12 secondary, header `.subheadline` medium, footer `bar` = callout medium | T `Typography.rowTitle/rowTrailing/sectionHeader/bar` |
| Ink | white 1.0 / 0.60 / 0.40, selection 0.10, control 0.10 | T `Colors.textPrimary/Secondary/Tertiary/selection/controlSurface` |
| Glyph slot | 20 pt slot, 16 pt mark (0.8 of the slot; the menu row's 14 read thin, D v3 review) in one ink (monochrome); a battery keeps its layers, since its fill against its frame is the level | T `Size.menuIcon` (HUD pill slot), `Typography.menuSymbolSize` (`SymbolImage` in upstream editors) |
| Pill grammar | glyph, `md` 8, text in `bar`; tone tints only the glyph; spinner `progress.indicator` + variableColor | T `MessageHUDView` |
| Ring | 14 pt ring, 2 pt stroke | T `Size.chatContextGauge`, `contextRingStroke` |
| Calendar bar | 3 × 18 | T `Size.calendarBarWidth/Height` |
| Motion | hover 0.12 easeOut, enter 0.18, exit 0.12, bead stagger 0.055; the island's own springs never bounce (§ Motion) | T `Duration`, `CompactBarMotion` |

## Surface (both shapes)
- Black, no border, no glass, no shadow on the closed shapes. D "cała czarna", approved rule "no border". Ink is the ramp's dark side (forced dark).
- One silhouette path for every state and the opening (`IslandSilhouette.path`): body with top corners, shoulders and bottom corners, plus one bubble circle that parks inside the body's trailing end at zero size. Same element count always, so every change morphs. ★ (makes the bubble bead out like Tinycast's compact-bar buttons, T `CompactBar`).

## Island (monitor) — the primary shape
| Rule | Value | Source |
|---|---|---|
| Gap under top edge | 4 | O 2 Nov decision; T `Spacing.xs` |
| Height | 36, the launcher's search row | T `Size.headerHeight`; D 2 and 5 Nov: both shapes and the launcher share one row |
| Shape | capsule | T compact bar and HUD pill are capsules |
| At rest | 144 × 36 (4 heights) | ★ reads as a pill, not a dot; D "small black pill" |
| Shorter content | stays 144 wide, content centred, so a short pill reads balanced instead of leaving its trailing half empty | ★ v3 QA: leading alignment left the right half empty |
| End insets | (36 − item)/2: cover 5, glyph 8; text and bars 8 | ★ concentric to the end cap, T ui.md "Concentric corners" |
| Gaps | item→text 8; text→trailing ≥ 12 | T HUD pill `md`; T `Spacing.xl` |
| Title width | follows the title, at most 200, then scrolls | D "width follows the title up to a limit"; T `Size.chatSourceTitle` 200 |
| Max width | 420 | T `Size.hudMaxWidth` (HUD pill ceiling) |
| Two at once | main pill + 36 pt bubble, 10 apart, bubble holds the second item's glyph | D; T `CompactBarMotion` "10pt gap" |

## Notch (internal display)
| Rule | Value | Source |
|---|---|---|
| At rest | exactly the hardware notch, shoulders 0 | D "hidden 1:1" |
| Wings | ≥ 44 = 20 + 2·12, grow to the wider side, both sides equal | T `menuIcon` + `Spacing.xl`; O ear 44 |
| Shoulders | 6 when anything shows | kit `Radius.thumbnail` (existing) |
| Bottom corners | height × 0.34, capped at 26 | kit `Corners.bottomRadius` (the existing ratio, the notch shape D named) |
| Word in wing | only when word + value ≤ 100 pt, else value only | D "a word only if it fits"; ★ 100 keeps the eye on the camera |
| Wing content | hugs the wing's outer edge, 12 in: leading mark left, word and value right | ★ the two sides balance however wide the wings grow |
| Below the camera | rows of 36 under the band (same row as the island pill), 12 side inset, 6 bottom; a row spans the body like a launcher row (lines left, value or button right), its text on the glyph's left edge | ★ one row height for both shapes |
| Two at once | second item as a row below the camera | D |

## Pieces (every state is built from these, nothing else)
`IslandGlyph` (symbol, white in one ink with no greyed layers, like the HUD pill's glyph; 20 slot; red only for error, orange only for warning), `IslandValueText` (the value type), `IslandLines` (title in `bar`, second line `.subheadline` textSecondary; one or two lines; scrolls past the limit), `IslandArtwork` (26 = T `Size.resultRowIcon`, radius 6 = T `Radius.thumbnail`, round in the pill's end), `IslandVisualizer` (Orion or DT), `IslandRing` (optional, levels), `IslandCardButton` (26 capsule, `controlSurface` / `controlHover` / `controlPressed` fill like T `ModalActionButtonStyle`, `bar` text = concentric 18 − 5 = 13), `IslandCalendarBar` (T `CalendarBar`).

## The value type (`IslandValue`)
`timeLeft(Date)`, `elapsed(since: Date)` / `elapsed(frozen: TimeInterval)`, `percent(Double)`, `count(Int, of: Int)` (X/Y), `step(Int, of: Int)` (island "Step X/Y", notch "X/Y"), `live(Double, unit)` (speed Mb/s, agents count), `toggle(Bool)` (on: 8 pt white dot, T `Size.colorDot`; off: Tinycast's own "Off" word, never a second glyph), `level(Double)` (bars still at that level), `spinner`, `pair(a, b)` (battery calibration: percent · step). All in `.callout` monospaced digits, white. An activity without an explicit value keeps today's mapping: end date → time left, progress → percent, else spinner.

## Visualizers
- Orion: 4 bars 3 × 14, gap 2, rest 0.6, low 0.3, 0.9 s ease cycle with offsets. O `MusicParts.swift` (`notch-detached-pill-paused`).
- DT: 7 bars 1.8 wide at 1.85 pitch, 14 high, Winamp fall (3 heights/s), hanging peaks, synthetic 6–12 readings/s. DT `NotchBars.swift`.
- Lab (Debug build only): `NOTCHCAST_VISUALIZER_LAB=1 "<DerivedData>/Build/Products/Debug/Notchcast Dev.app/Contents/MacOS/Notchcast Dev"` opens one window with both in the closed music pill, playing, and a Playing switch. Gallery still: `island-visualizer-lab.png`.
- With motion off (Reduce Motion, Show animations off, the gallery), a playing song holds one frame of Orion's sway (each bar at its own offset); paused rests flat at 0.6. ★ so playing and paused stay apart without motion.
- Default in closed states: Orion. ★ D liked how Orion's bars looked ("wyglądało dość legitnie"); both play side by side in the debug lab for his pick. Paused = still at rest level (D).

## Messages and cards
- Island message = the music layout with a glyph in the cover slot: one line, or title + description on two lines. Notch: short ones (≤ 100) glyph left / text right; longer go below the camera, ≤ 2 lines. D.
- Meeting: calendar bar, title, "in 5 min", Join. Timer end: glyph, title, "Done", Stop only. D.
- Who is main: a message, then live activities by rank (a meeting reminder becomes its card), then the song; the second in line goes to the bubble (island) or the row below the camera (notch). ★ a message is short-lived and answers what you just did; music is the background.
- Tone: only real problems get colour. Low battery, low disk, Wi-Fi or Tailscale down are warnings (orange glyph); failures are errors (red glyph). Everything else is white. D "only error and warning get colour".
- Glyphs: a producer names its subject's symbol (speaker, sun, headphones, wifi, network, battery, internal drive, walking figure, calendar); a message without one takes its tone's glyph (info, checkmark, exclamation mark, the spinner while working), like T `MessageHUDView`.
- Removed: "Second Cmd+Q quits" — no closed state, no gallery page (QuitProtection's notice has no island reader on main; nothing added). D.

## Motion
- State to state: one CA spring per morph, picked by whether the outline's bounds grow (`IslandMotion.choice`). No island spring bounces: the one outline carries the row that meets the notch, and an overshoot would show the screen behind it. Growing (a closed state widening, a bubble beading out, closed to open) runs on 0.28/0 (T `Duration.settingsReveal`); shrinking (open to closed, a closed state narrowing) on 0.18/0 (T `Duration.enter`). Every morph starts from the shape on screen, so an interrupted one retargets without a jump. Content swaps with 0.12 easeOut. Kit `IslandMotion`, T `Duration.hover`.
- Launcher from the island (both shapes): the launcher is Tinycast's own Liquid Glass panel hung under the island, with the palette's glass, shadow, light or dark appearance, window level and window animation. The island stays closed and visible above it; nothing grows and nothing is painted black. D (10 Nov) "zaaplikowało do naszego launchera Liquid Glass ten tinycastowy bo z jakiegoś powodu jest wszystko czarne". This replaces v4's black surface that grew out of the island (D "mikro wersja, cała czarna … rozrasta się do obecnego launchera"): the black hid the glass, forced Dark in Light, covered the menu bar and could leave a black band above the search field.
- Retired, still in the tree: nothing in the app starts `IslandPanel.growIntoLauncher` any more, so `launcherOutline` and `NotchcastTheme.Opening` serve only the gallery's opening frames (`island-opening-*`, `launcher-opening-end-*`) and the motion stage, which show a motion the app no longer plays; `launcherDidClose` still runs when the launcher leaves (`restoreAfterLauncher`) but does nothing, since no island grew.
- Placement: the launcher hangs under the island, centred on it, `NotchcastLauncherGeometry.gap` (8, T `Spacing.md`) below the closed body's bottom edge at the moment it opens. Notch at rest: the notch's bottom; with a row shown below the camera, that row's bottom, so the island never covers the search field. Monitor: the pill's bottom. It never covers the menu bar. A body that grows while the launcher is up is not followed. With Launcher from Island off, or no island on the active space, the launcher keeps its own spot.
- One surface at a time: the launcher showing closes an open island it hangs from or would sit under (covering or touching it), pinned or not; an open island elsewhere, such as with Launcher from Island off and the launcher at its own spot, stays open. Closing the launcher returns focus to the app behind it, never the island. State machine: `notchcast/docs/island-launcher-states.md`.

## Polish rules (second pass)
- Signature, concentric corners: a piece inside the black follows the shape that holds it. In the pill's end the 26 cover sits 5 in, so its corner is 18 − 5 = 13 (round), and the bubble's cover is round too; in a notch wing it keeps the notch corner's small radius (6). The card button was already a capsule (13).
- Colour lives in the content only: the album cover and the calendar bar. Warnings and errors tint only their glyph.
- One moving thing: work without a number spins in the glyph slot (`progress.indicator`, like Tinycast's progress HUD) and shows no trailing spinner. A status with nothing to count shows its glyph alone, never a spinner.
- A mark never parts from its text: when a notch item's text goes below the camera, its glyph or calendar bar goes with it and the wings stay black.
- Rows below the camera share one leading column 26 wide (the cover's width), so every title starts on one line.
- Copy: one-line notices end without a period ("Daily walking goal reached").
