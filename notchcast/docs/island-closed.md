# Closed notch, closed island, opening into the launcher — rule sheet

One design, two shapes. Every value lives in `Tinycast/Features/Notchcast/Island/NotchcastTheme.swift` (`Closed`, `Value`, `Visualizer`, `Opening` groups) or comes straight from Tinycast's `Theme`. Sources: **T** = Tinycast code (`Theme.swift` line), **L** = measured on the launcher (`refs/1-tinycast-launcher.png`, 2× capture, 750 pt panel = 1500 px), **D** = Damian's words in `look-decisions.md`, **O** = Orion (shape/music layout/visualizer, named by D), **DT** = Damian Tools visualizer, **★** = my taste call (reason given).

## Measured launcher (the yardstick)
| What | Value | Source |
|---|---|---|
| Panel | 750 × 475, radius 26 continuous, compact 56 capsule | T `Size.panelWidth/Height`, `Radius.panel`, `Size.compactHeight`; L 1500 px wide |
| Row | 26 icon, 10 icon→title, 8/6 insets, pitch 38, radius 10 | T `resultRowIcon`, `Spacing.lg/md/sm`, `Radius.row`; L rows 65 px apart |
| Type | title `.body` 13, trailing `.callout` 12 secondary, header `.subheadline` medium, footer `bar` = callout medium | T `Typography.rowTitle/rowTrailing/sectionHeader/bar` |
| Ink | white 1.0 / 0.60 / 0.40, selection 0.10, control 0.10 | T `Colors.textPrimary/Secondary/Tertiary/selection/controlSurface` |
| Glyph slot | 20 pt slot, body-size symbol | T `Size.menuIcon`, `Typography.menuIcon` (HUD pill) |
| Pill grammar | glyph, `md` 8, text in `bar`; tone tints only the glyph; spinner `progress.indicator` + variableColor | T `MessageHUDView` |
| Ring | 14 pt ring, 2 pt stroke | T `Size.chatContextGauge`, `contextRingStroke` |
| Calendar bar | 3 × 18 | T `Size.calendarBarWidth/Height` |
| Motion | hover 0.12 easeOut, enter 0.18, exit 0.12, capsule spring 0.44/0.62, bead stagger 0.055 | T `Duration`, `CompactBarMotion` |

## Surface (both shapes)
- Black, no border, no glass, no shadow on the closed shapes. D "cała czarna", approved rule "no border". Ink is the ramp's dark side (forced dark).
- One silhouette path for every state and the opening (`IslandSilhouette.path`): body with top corners, shoulders and bottom corners, plus one bubble circle that parks inside the body's trailing end at zero size. Same element count always, so every change morphs. ★ (makes the bubble bead out like Tinycast's compact-bar buttons, T `CompactBar`).

## Island (monitor) — the primary shape
| Rule | Value | Source |
|---|---|---|
| Gap under top edge | 4 | O 2 Nov decision; T `Spacing.xs` |
| Height | 30 = 22 + 2·4 | T `Size.headerIconSlot` 22 + `Spacing.xs`; O pill 30 (ref 4: 58 px) |
| Shape | capsule | T compact bar and HUD pill are capsules |
| At rest | 120 × 30 (4 heights) | ★ reads as a pill, not a dot; D "small black pill" |
| End insets | (30 − item)/2: cover 4, glyph 5, text and bars 8 | ★ concentric to the end cap, T ui.md "Concentric corners" |
| Gaps | item→text 8; text→trailing ≥ 12 | T HUD pill `md`; T `Spacing.xl` |
| Title width | follows the title, at most 200, then scrolls | D "width follows the title up to a limit"; T `Size.chatSourceTitle` 200 |
| Max width | 420 | T `Size.hudMaxWidth` (HUD pill ceiling) |
| Two at once | main pill + 30 pt bubble, 10 apart, bubble holds the second item's glyph | D; T `CompactBarMotion` "10pt gap" |

## Notch (internal display)
| Rule | Value | Source |
|---|---|---|
| At rest | exactly the hardware notch, shoulders 0 | D "hidden 1:1" |
| Wings | ≥ 44 = 20 + 2·12, grow to the wider side, both sides equal | T `menuIcon` + `Spacing.xl`; O ear 44 |
| Shoulders | 6 when anything shows | kit `Radius.thumbnail` (existing) |
| Bottom corners | height × 0.34, capped at 26 | kit `Corners.bottomRadius` (the existing ratio, the notch shape D named) |
| Word in wing | only when word + value ≤ 100 pt, else value only | D "a word only if it fits"; ★ 100 keeps the eye on the camera |
| Wing content | hugs the wing's outer edge, 12 in: leading mark left, word and value right | ★ the two sides balance however wide the wings grow |
| Below the camera | rows of 30 under the band (same row as the island pill), 12 side inset, 6 bottom; a row spans the body like a launcher row (lines left, value or button right), its text on the glyph's left edge | ★ one row height for both shapes |
| Two at once | second item as a row below the camera | D |

## Pieces (every state is built from these, nothing else)
`IslandGlyph` (symbol, white, 20 slot; red only for error, orange only for warning), `IslandValueText` (the value type), `IslandLines` (title in `bar`, second line `.subheadline` textSecondary; one or two lines; scrolls past the limit), `IslandArtwork` (22, radius 6 = T `Radius.thumbnail`), `IslandVisualizer` (Orion or DT), `IslandRing` (optional, levels), `IslandCardButton` (22 capsule, `controlSurface` fill, `bar` text = concentric 15 − 4 = 11), `IslandCalendarBar` (T `CalendarBar`).

## The value type (`IslandValue`)
`timeLeft(Date)`, `elapsed(since: Date)` / `elapsed(frozen: TimeInterval)`, `percent(Double)`, `count(Int, of: Int)` (X/Y), `step(Int, of: Int)` (island "Step X/Y", notch "X/Y"), `live(Double, unit)` (speed Mb/s, agents count), `toggle(Bool)` (on/off: 8 pt dot, T `Size.colorDot`, white on / tertiary off), `level(Double)` (bars still at that level), `spinner`, `pair(a, b)` (battery calibration: percent · step). All in `.callout` monospaced digits, white. An activity without an explicit value keeps today's mapping: end date → time left, progress → percent, else spinner.

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
- State to state: kit springs (grow 0.44/0.25 wide, shrink no bounce); content swaps with 0.12 easeOut. Kit `IslandMotion`, T `Duration.hover`.
- Opening (both shapes): launcher shows → the black silhouette springs from its closed shape to the launcher's own frame and corner (compact 56 capsule or panel 26) in 0.28 s, closed content fades out in 0.12, then the black dissolves in 0.12 (T `Duration.exit`) onto the glass launcher. While the launcher is open the island hides; when it closes the island fades back in 0.18 (T `Duration.enter`). Reduce Motion or animations off: no morph, plain fade. D "mikro wersja, cała czarna … rozrasta się do obecnego launchera".
- Gallery frames: start = the closed state; middle = the black halfway between closed and the launcher's frame (content already gone); end = the black in the launcher's exact frame and corner, the instant before it dissolves (glass cannot render offscreen, so the glass itself is in the launcher pages).
- Launcher sits 8 under the island's closed body, never its bubble (T `Spacing.md`, existing `launcherGap`). It cannot cover the menu bar (palette level is below it), so the launcher never takes the island's own spot. ★
