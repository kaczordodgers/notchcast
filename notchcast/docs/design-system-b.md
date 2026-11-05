# Tinycast design system (for Notchcast features), design B

The design system as design B leaves it: `design-system.md` carried forward with what the island work on `nc-design-race-b-v3` settled, read against the `design-system-patterns` skill (wshobson/agents, `plugins/ui-design/skills/design-system-patterns`) and accepted by Damian on 5 Nov. §0–§14 are upstream's rules with the island's additions in place; §15 names the token tiers and how a token changes in a fork that cannot touch its primitives; §16 is the island kit as the component tier; §17 the catalogue and its checks; §18 what the skill says that does not apply to a native app. Citations into `Tinycast/Features/Notchcast/` are against 14d5c2b6. The original `design-system.md` is untouched until the race is decided.

Source: read-only clone of upstream `abue-ammar/tinycast` at HEAD `3be769dc`. All `path:line` citations are relative to that clone. The goal: a Notchcast feature should look as if the upstream author shipped it. This is **Tinycast's** system (native Liquid Glass + an alpha ink ramp), not any other design system. Upstream's own spec is `docs/ui.md` (907 lines) and it is authoritative and largely accurate; this file condenses it, ties each rule to code and records where the doc and the code disagree.

## 0. Where a notch UI fits

Tinycast has no notch surface (see `architecture.md` §1). The nearest upstream models, best first:

1. **Compact bar** (`Tinycast/Features/Launcher/UI/CompactBar.swift:53-67`): a `.regular` glass `Capsule` with glass circles beading out of it inside one `GlassEffectContainer`, springs from `Theme.CompactBarMotion` (`Tinycast/DesignSystem/Theme.swift:338-357`), glyphs drawn above the container (`CompactBar.swift:68-73`). Use it as the model for a notch pill that expands and contracts.
2. **Message HUD pill** (`Tinycast/Windows/HUD/MessageHUDView.swift:47-64`, panel `Tinycast/Windows/HUD/HUDPanel.swift:4-25`): a never-key, click-through, `.palette`-level capsule for transient status. Use it for notch status readouts.
3. **Camera panel** (`Tinycast/Features/Camera/UI/CameraPanel.swift:14-35`, view `Tinycast/Features/Camera/UI/CameraView.swift:6-17`): a borderless, non-activating, `.floating` glass panel with matte footer buttons; ↵/Esc handled in `sendEvent` (`CameraPanel.swift:37-50`). Use it as the model for an expanded notch panel that takes keys.
4. **Notes panel** (`Tinycast/Features/Notes/UI/NotesPanel.swift:19-39`): the model for a titled, resizable floating panel that persists through focus loss.
5. **Palette** (`Tinycast/Palette/PalettePanel.swift:259-274`, `Tinycast/Palette/RootPaletteView.swift:343-362`): the full recipe for a list surface (rows, section headers, edge dissolve, floating bars).

## 1. Shared UI components

All in `Tinycast/DesignSystem/` unless noted. Reuse before you build; `docs/ui.md:740-747` lists what is deliberately shared.

| Component | Definition | Use when |
| --- | --- | --- |
| `Theme` (tokens) | `Tinycast/DesignSystem/Theme.swift:4` | every number and colour; add a token, never a literal (`docs/ui.md:72-73`) |
| `InterfaceMetrics` + `@Environment(\.metrics)` | `Tinycast/DesignSystem/InterfaceMetrics.swift:4`, env key `:226-229` | any view on a scaled surface (palette, menus, dialogs, HUDs) reads `metrics.spacing/size/radius/typography`, not `Theme.*` directly (`docs/ui.md:81-85`) |
| `GlassEffectView` | `Tinycast/DesignSystem/GlassEffectView.swift:3-9` | the root surface of a borderless panel: `.background(GlassEffectView())` then `.clipShape(...)` |
| `View.frosted(in:)` | `Tinycast/DesignSystem/Theme.swift:533-537` | floating glass controls (footer capsule, menu circle); `.regular.interactive()` |
| `BarButton` / `BarButtonChrome` | `Tinycast/DesignSystem/BarButton.swift:24-67` | any bar/header/footer control: bare at rest, `rowHover` on hover, `selection` when `isSelected` |
| `HeaderMenuButton` | `Tinycast/DesignSystem/BarButton.swift:69` | a header pop-up that names a value and drops a menu (rounded `barControl` chrome) |
| `PopoverMenu` / `PopoverMenuItem` / `PopoverMenuIcon` | `Tinycast/DesignSystem/PopoverMenu.swift:70`, `:18`, `:3` | every in-window menu; never `.contextMenu`/`NSMenu` in a panel (`docs/ui.md:465`) |
| `KeyCapChip` | `Tinycast/DesignSystem/KeyCapChip.swift:4` | shortcut hints: `.outline` on rows, `.filled` in the footer; `Scale` compact/standard/hero (`:40-51`) |
| `Tooltip` (`.tooltip(_:)`, `.tooltip(keyCaps:)`) | `Tinycast/DesignSystem/Tooltip.swift:79-96` | hover labels in any non-activating panel (never `.help()` there) |
| `ModalActionButtonStyle` (`.modalAction(role)`) | `Tinycast/DesignSystem/ModalActionButtonStyle.swift:3-75` | matte capsule buttons on borderless surfaces: dialogs, editors, camera footer, Quick Action panel |
| `SymbolImage` | `Tinycast/DesignSystem/SymbolImage.swift:4-30` | every glyph whose name could be a bundled asset; falls back from SF Symbol to `Assets.xcassets` |
| `SectionHeader` | `Tinycast/Features/Launcher/UI/SectionHeader.swift:3-32` | category labels in every palette list |
| `SettingsRow`, `SettingsTabIcon`, `SettingsFeatureToggleLabel`, `FeatureSwitchSection`, `SettingsFilterField`, `SettingsEditorHeader`, `SettingsEditorField` | `Tinycast/DesignSystem/SettingsComponents.swift:52`, `:6`, `:30`, `:298`, `:336`, `:209`, `:227` | Settings panes and editors (§6) |
| `RevealableSecureField` | `Tinycast/DesignSystem/RevealableSecureField.swift:4` | any secret in Settings, never a bare `SecureField` (`docs/ui.md:703-706`) |
| `SteadySegmentedPicker` | `Tinycast/DesignSystem/SteadySegmentedPicker.swift:5` | a segmented control shown in a freshly opened panel |
| `Motion` / `motionScope()` | `Tinycast/DesignSystem/Interaction/Motion.swift:5-24` | every hosting root (§10) |
| `AnimatedPanel.followMotion()` | `Tinycast/DesignSystem/Interaction/AnimatedPanel.swift:5-11` | every `NSPanel` that opens/closes with `.documentWindow` |
| `fadeIn` / `fadeOut` / `panelEntrance()` | `Tinycast/DesignSystem/Interaction/PanelTransition.swift:8`, `:25`, `:99` | non-documentWindow panel fades (HUDs, room preview) |
| `edgeDissolve()` / `overflowFade()` / `thinScrollbar()` | `Tinycast/DesignSystem/Scrolling/EdgeDissolve.swift:72`, `OverflowFade.swift:78`, `ThinScrollbar.swift:173` | list edges; EdgeDissolve and ThinScrollbar are **off-limits to edit** (`AGENTS.md`, Non-negotiables) |
| `WindowDragHandle` / `windowDraggable` / `WindowDragBackground` | `Tinycast/DesignSystem/Interaction/WindowDragHandle.swift:4`, `:17`, `:29` | drag-to-move on borderless panels |
| `armedHover(_:)` | `Tinycast/Palette/ArmedHover.swift:22` | row hover in a keyboard-driven list (hover only after real pointer movement) |
| `DialogController` (`confirm`, `choose`, `notice`, `reportFailure`) | `Tinycast/Windows/Dialog/DialogController.swift:17`, `:32`, `:42`, `:51` | every question or failure; never `NSAlert` |
| `AppCore.showMessage` / `showProgress` | `Tinycast/App/AppCore.swift:992-999` | every transient success/info/progress readout |

## 2. Spacing and padding

Scale (`Tinycast/DesignSystem/Theme.swift:5-28`): `xxs 2` · `xs 4` · `sm 6` · `md 8` · `lg 10` · `xl 12` · `dialogInset 18` · `xxl 20` · `xxxl 28`; plus `sectionHeaderBottom 4` (`:17`), `sectionSpacing 12` (`:25`).

Rules to imitate:

- Row: `HStack(spacing: lg)`, `.padding(.horizontal, md)`, `.padding(.vertical, sm)` (`Tinycast/Features/Launcher/UI/LauncherList.swift:314`, `:375-376`). List horizontal inset is also `md` (`LauncherList.swift:221`).
- Keycaps side by side: `xxs` (`LauncherList.swift:351`, `:363`).
- Panel footer: `.padding(Theme.Spacing.xl)` with `md` between buttons (`Tinycast/Features/Camera/UI/CameraView.swift:25`, `:49`).
- HUD pill: horizontal `xl`, vertical `lg`, glyph→text `md` (`Tinycast/Windows/HUD/MessageHUDView.swift:48`, `:55-56`).
- Empty/unavailable state: `VStack(spacing: md)`, `.padding(xxl)` (`Tinycast/Features/Camera/UI/CameraStage.swift:20`, `:27`).
- Settings row: icon→text `lg`, title→subtitle `xxs` (`Tinycast/DesignSystem/SettingsComponents.swift:64-66`).
- Concentric corners: inner radius = outer radius − gap (`menuPanel 16` − `sm 6` = `menuRow 10`), but alignment to the triggering control beats it (`docs/ui.md:140-168`).

## 3. Typography

System text styles only; no fixed sizes in views (`docs/ui.md:208-211`). Tokens at `Tinycast/DesignSystem/Theme.swift:365-404`:

- `rowTitle` = `.body` (`:374`), `rowTrailing` = `.callout` (`:375`), `sectionHeader` = `.subheadline.weight(.medium)` (`:376`), `panelTitle` = `.headline` (`:378`), `bar` = `.callout.weight(.medium)` (`:389`), `keyCap` = `.caption` (`:380`), `menuRow` = `.body` (`:395`).
- Sanctioned fixed sizes: `searchField` 20pt Regular (`:367-368`), `headerIcon` 18pt Medium (`:372-373`), `menuSymbolSize` 14pt Medium (`:398-399`).
- Secondary text uses `.foregroundStyle(.secondary)` or `Theme.Colors.textSecondary`, never a smaller custom font (`LauncherList.swift:333-337`).
- Settings subtitles: `.caption` + `.secondary` in `SettingsRow` (`SettingsComponents.swift:76-78`); `.subheadline` in a feature master switch (`SettingsComponents.swift:43-45`).
- Numbers that change in place: monospaced digits in a fixed-width slot (`volumeReadout 38`, `docs/ui.md:554-567`).
- Scaling rebuilds a font from its own descriptor; never a `.system(size:weight:)` weight table (`docs/ui.md:213-217`).

## 4. Colours and materials

- **The ramp.** `Theme.Colors.ramp(dark:light:)` (`Tinycast/DesignSystem/Theme.swift:413-415`): white ink at alpha *n* in Dark, black ink in Light. `adaptive(dark:light:)` (`:408-410`) for anything that is not a plain inversion. Dark values are frozen; Light may be retuned (`docs/ui.md:37-38`).
- Core stops (`Theme.swift:433-463`): `selection` 0.10 (`:433`), `rowHover` 0.05 (`:434`), `menuHover` 0.10 (`:440`), `separator` 0.10 (`:441`), `controlSurface` 0.10 (`:443`), `controlHover` 0.16 (`:444`), `controlPressed` 0.24 (`:446`), `border` 0.20 (`:452`), `textPrimary/Secondary/Tertiary` 1.0/0.60/0.40 (`:454-456`), `cardFill` 0.05 / `cardStroke` 0.10 (`:462-463`).
- Fixed hues (`Theme.swift:487-502`): `brand` purple (`:487`), `primaryAction` blue (`:492`), `destructive` red (`:493`), `success` green (`:494`), `warning` orange (`:495`), `progress` blue (`:502`).
- **Never** `Color.white.opacity`, `.gray` or `NSColor.windowBackgroundColor` on a surface (`docs/ui.md:38-39`). A grep of `Tinycast/` outside Extensions finds none.
- **Materials.** Borderless panel surface: `GlassEffectView()` then one continuous clip. Palette root `Tinycast/Palette/RootPaletteView.swift:346` + `:358-362`; Notes `Tinycast/Features/Notes/UI/NotesView.swift:12-13`; Camera `CameraView.swift:15-16`; HUD pill `MessageHUDView.swift:61-62`; volume HUD `Tinycast/Windows/HUD/VolumeHUDView.swift:39-40`. Floating controls: `.frosted(in:)` or `.glassEffect(.regular, in:)`; menus `PopoverMenu.swift:131`. No scrim over glass, no hand-tuned shadow on glass (`docs/ui.md:467`); the window's native `hasShadow = true` gives the elevation.
- Panel window recipe: `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`, `followMotion()` (`PalettePanel.swift:271-274`, `NotesPanel.swift:32-35`, `CameraPanel.swift:28-31`).
- Tone tints: `DialogTone` `.neutral`/`.success`/`.danger` (`Tinycast/Windows/Dialog/DialogRequest.swift:16-19`) colour only the glyph.

## 5. Icons

- SF Symbols, mostly `.hierarchical`; `.monochrome` when selected or in menus (`SymbolImage.swift:25-27`). Resolve through `SymbolImage`, never raw `Image(systemName:)` for catalog symbols, because some are bundled (`docs/ui.md:58`).
- Custom assets in `Tinycast/Assets.xcassets`: AI brand marks (`AIBrand*`), `BrandDiscord/GitHub/X`, `MenuBarIcon`, `WindowModeCompact/Expanded`, `bluetooth` (a trademark, so shipped as art; `docs/ui.md:490-493`).
- Dark-variant swap: `SystemSymbolName.resolve` (`Tinycast/Platform/Images/IconCache.swift:45-50`).
- Slot sizes: palette rows always a 26pt `resultRowIcon` slot (`Theme.swift:115`, used `LauncherList.swift:315-316`); menus a 20pt `menuIcon` slot (`Theme.swift:174`); header glyph 18pt (`Theme.swift:372`); dialog icon 32pt (`Theme.swift:270`); Settings row icon 20pt (`Theme.swift:199`).
- A dialog's icon is the subject's own glyph (a command's `sfSymbol`), never chosen by tone (`docs/ui.md:57`, `:487-493`). A HUD pill's glyph *is* the tone: `info` / `checkmark` / `exclamationmark` (`MessageHUDView.swift:124-129`).
- Settings sidebar tile: glyph tinted, on `tint.opacity(0.1)` in a `thumbnail` rounded rect (`SettingsComponents.swift:6-28`).
- App icons go through `IconCache` and key on its style generation (`docs/ui.md:41`).

## 6. Settings pane pattern

- Every pane is `Form { Section { … } header: { SettingsSectionHeader(anchor) } }.formStyle(.grouped).settingsScrollTarget(tab)`. Canonical: `Tinycast/Features/Notes/Settings/NotesSettingsView.swift:9-53`, `Tinycast/Features/Settings/Panes/NavigationSettingsView.swift:10-52`.
- Feature master switch first, in its own section: `Toggle { SettingsFeatureToggleLabel(anchor:title:subtitle:) }` + `.settingsAnchor(...)` (`NotesSettingsView.swift:10-17`), or `FeatureSwitchSection` when the feature also has a "Show in launcher" companion (`SettingsComponents.swift:298-333`; used at `Tinycast/Features/Snippets/Settings/SnippetsSettingsView.swift:12-15`).
- A row is a stock control with a two-view label: title via `SettingsRowTitle(anchor, "…")`, then `Text("…")` becomes the subtitle (`Tinycast/Features/Settings/Panes/GeneralSettingsView.swift:32-35`). Custom trailing control: `SettingsRow` (`SettingsComponents.swift:52-90`), because `LabeledContent` eats recorder taps (`docs/ui.md:689-692`).
- Dependent rows: `.settingsEnabled(_:)` (dims to 0.45 and disables) (`SettingsComponents.swift:186-188`; used `NotesSettingsView.swift:24`, `:28`).
- Buttons in a row trail inside `LabeledContent`; an action that opens a picker ends in "…" ("Choose…", `NotesSettingsView.swift:40`); a destructive one uses `role: .destructive` and confirms ("Reset…", `GeneralSettingsView.swift:133`).
- Every anchor is declared once (`Tinycast/Features/Settings/SettingsAnchor.swift:76-77`) and every row is listed in `SettingsSearchCatalog` (`Tinycast/Features/Settings/SettingsSearchCatalog.swift:387-399`); `Scripts/check-settings-search.js` (run by lint) fails a missing pair (`docs/ui.md:771-788`). Definitions: `SettingsSectionHeader` `Tinycast/Features/Settings/SettingsScrollTarget.swift:40`, `SettingsRowTitle` `:58`, `.settingsAnchor` `:13`.
- In Settings use `.help()` for hover text (the window activates the app); `launcherVisibilityHelp()` is the shared one (`SettingsComponents.swift:204-206`).
- New preference also needs a `SettingsFileKey` + `SettingsFileSchema` binding (`AGENTS.md`, Conventions).

## 7. Launcher/palette rows and lists

- Canonical row: `AppRow` (`Tinycast/Features/Launcher/UI/LauncherList.swift:285-383`). Leading 26pt icon, `rowTitle` title `lineLimit(1)`, optional secondary subtitle/alias, outline keycaps, `Spacer()`, trailing kind label in `rowTrailing` + `.secondary`.
- Fill precedence selection → hover → clear (`LauncherList.swift:302-306`) on `RoundedRectangle(radius.row 10, .continuous)` (`:377-380`); this `fill` is copy-identical across `AppRow`, `ClipboardRow`, `UninstallRow` and must stay so (`docs/ui.md:433`).
- Hover state lives on the row and is armed by pointer movement: `.armedHover($hovered)` (`LauncherList.swift:381`).
- Selected row marked with `.selectionFrame(...)` for scroll-follow (`LauncherList.swift:191`); the list takes `.edgeDissolve()` before `.thinScrollbar()` (`LauncherList.swift:227`).
- Section header: `SectionHeader(title:isFirst:)` (`SectionHeader.swift:3-32`), `.subheadline.medium`, secondary, `md` horizontal; the first header skips the top gap.
- Menus: `PopoverMenu` rows in a `LazyVStack`, fixed width per menu, empty state "No Results" centred in one row in `textTertiary` (`PopoverMenu.swift:150-160`).

## 8. Floating panel pattern

- `NSPanel` subclass conforming to `AnimatedPanel`; style `[.borderless, .fullSizeContentView, .nonactivatingPanel]`; `isFloatingPanel = true`; `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`; clear, non-opaque, `hasShadow`, `followMotion()`; `isReleasedWhenClosed = false`, `isRestorable = false` (`CameraPanel.swift:14-35`).
- Levels: HUDs `.palette` and never key (`HUDPanel.swift:15`, `:23-24`); palette `.palette` (`PalettePanel.swift:266`); Notes and Camera `.floating` so a dialog lands above (`NotesPanel.swift:29`, `CameraPanel.swift:22-23`).
- Keys in `sendEvent` (↵ primary, Esc cancel) so nothing needs focus (`CameraPanel.swift:37-50`).
- Root view: content → `.background(GlassEffectView())` → `.clipShape(RoundedRectangle(radius, .continuous))`, clip last (`CameraView.swift:14-16`). Hosting view root gets `.motionScope()` (`Tinycast/Features/Camera/UI/CameraCoordinator.swift:73`, `Tinycast/Windows/HUD/HUDPresenter.swift:28`).
- Footer actions: `CameraButton` → `.buttonStyle(.modalAction(role, fillsWidth: false))` + `.tooltip(keyCaps:)` (`Tinycast/Features/Camera/UI/CameraButton.swift:15-19`); Cancel/Close leading, primary trailing (`CameraView.swift:39-47`).
- Transient readouts go through `HUDPresenter` (one at a time, replace, never stack); a new HUD shape is a new presenter (`docs/ui.md:600-608`).
- Corner radii: palette and dialogs `panel 26` (`Theme.swift:31`); Camera and volume HUD `dialog 20` (`Theme.swift:43`); pill/compact bar `Capsule`.
- **Window levels are the z-scale.** The skill keeps a z-index scale as tokens; here it is `NSWindow.Level`, and the table is: island `statusBar + 1` (`Island/IslandPanel.swift:65`), so the closed row sits over a black menu bar and under nothing; palette `.palette` (`PalettePanel.swift:267`); HUDs `.palette`, never key; Notes and Camera `.floating`. A surface that grows into another surface's frame must give way, not out-level it: the island's black fades out under the launcher's glass (`NotchcastTheme.Motion.blackOut/blackIn`, `Island/IslandPanel.swift:170`) because the palette sits below the island's level. Found in v3: before that fade the whole black covered the launcher beside a camera.

## 9. Copy and wording

Tone: plain, short, calm, second person when needed, no exclamation marks, no "please". Every user string is localized (`String(localized:)` when it travels as `String`, literal otherwise) and translated into all eight languages in the same change (`AGENTS.md`, Conventions; `docs/standards.md:242-272`). One sentence = one literal; counts are interpolated with catalog plurals (`docs/standards.md:261-265`).

Capitalization as shipped:

- **Command names, button labels, HUD outcomes: Title Case.** "Take Photo", "Switch Camera", "Mirror", "Close" (`CameraView.swift:28-44`); "Set Volume" (`DialogController.swift:69`, `:73`); "Trash Emptied" (`Tinycast/Features/SystemActions/Service/SystemActionRunner.swift:126`), "Hidden Files Shown" (`:141`), "Bluetooth Off" (`:162`); "Nothing to Import" (`Tinycast/Features/Snippets/UI/SnippetCoordinator.swift:157`).
- **Confirmation titles: a question.** "Enable Dictation?" (`Tinycast/App/AppCore.swift:100`), "Relaunch Tinycast?" (`AppCore.swift:818`), "Restart your Mac?" (`Tinycast/Features/SystemActions/Model/SystemAction.swift:157`), "Log out now?" (`SystemAction.swift:162`). Confirm button is the verb ("Continue", `AppCore.swift:106`); dismiss is "Cancel" (`DialogController.swift:19`); a notice's only button is "OK" (`DialogController.swift:45`).
- **Failure titles:** "“\(name)” Failed" (`Tinycast/Features/SystemActions/UI/SystemActionCoordinator.swift:100`) or sentence-case "Couldn't create the event" with a one-sentence cause "No calendar on this Mac accepts new events." (`Tinycast/Features/Calendar/UI/CalendarCoordinator.swift:308-309`).
- **Settings toggles: mostly sentence case**, subtitle a short consequence: "Show in menu bar" / "Shortcuts still work when the menu bar icon is hidden." (`GeneralSettingsView.swift:33-34`), "Show animations" (`:81`), "Enable snippets" / "Expand templates from the launcher or by keyword." (`SnippetsSettingsView.swift:14-15`). Master-switch subtitle states what the feature is in one sentence: "Plain Markdown in a floating editor." (`NotesSettingsView.swift:14`).
- **Empty states:** "No Results" in menus (`PopoverMenu.swift:156`); "Nothing here yet." in Settings lists (`Tinycast/Features/Launcher/Settings/LauncherItemsSection.swift:33`); an unavailable surface states the fact, centred, secondary: "No camera on this Mac.", "Tinycast has no access to the camera." (`CameraStage.swift:13-15`).
- **Progress:** gerund + ellipsis "Fixing Grammar…" (`docs/ui.md:589`); short confirmations "Copied path" (`Tinycast/Features/FileSearch/UI/FileSearchCoordinator.swift:132`).
- Ellipsis is the single "…" character; curly quotes around names.
- Words are rationed: a subtitle only where the title leaves out a consequence or limit; a footer only for a caveat (privacy, cost) (`docs/ui.md:715-719`).

## 10. Animation and timing

- One global switch: General → Appearance → "Show animations" → `Motion.isEnabled` via `AppCore.applyMotion()` (`AppCore.swift:804-809`, `Motion.swift:5-12`). Every hosting root applies `.motionScope()` (`Motion.swift:16-23`); AppKit groups take `Motion.duration(_:)` (`Motion.swift:9-11`); panels `followMotion()` (`AnimatedPanel.swift:8-10`). No view checks the setting itself. Activity indicators keep running (`docs/ui.md:47-56`).
- Durations (`Theme.swift:306-331`): `enter 0.18` / `exit 0.12` (`:311-312`), `dialogEnter 0.12` / `dialogExit 0.10` (`:314-315`), `hover 0.12` (`:320`), `tooltipDelay 0.4` + `tooltip 0.15` (`:317-319`), `messageHUD 2.4` (`:308`), `volumeHUD 1.6` (`:309`), `menuChevron 0.34` (`:321`), `copyFeedback 1.2` (`:322`).
- Curves: hover `.easeOut(duration: Theme.Duration.hover)` (`ModalActionButtonStyle.swift:30`, `MessageHUDView.swift:33`); disclosure `MenuMotion.chevronAnimation` timingCurve(0.16, 1, 0.3, 1) (`Theme.swift:359-363`); glass morph springs `CompactBarMotion.capsule` spring(0.44, 0.62) / `.button` spring(0.44, 0.86), staggered 0.055s (`Theme.swift:344-356`); glide `RoomMotion.glide` (`Theme.swift:333-336`).
- Panels open/close with AppKit's `.documentWindow` animation, not a SwiftUI scale (`docs/ui.md:545-550`).
- Glyph reveal: opacity + blur(4) after the glass settles (`CompactBar.swift:114-116`).
- **The island's motion tokens are aliases of the above** (`Island/NotchcastTheme.swift:153-165`): outline springs with `bounce: 0`, `grow` on `settingsReveal` 0.28 (open, and any closed change), `shrink` on `enter` 0.18; content in on `dialogEnter` 0.12, out on `exit` 0.12; `contentHold` = `CompactBarMotion.stagger` 0.055; `landing` = `CompactBarMotion.revealDelay` 0.12; the black under the launcher `exit`/`enter`. A notch island never bounces: the launcher's capsule spring (0.44, 0.62) undershot and left the island shorter than the notch for 0.4 s.
- **Handover of a changing closed row** (`Island/IslandMotion.swift:49-62`): a value ticking in place, a pause or the same message cuts; rows that share a piece hold one `contentHold` beat (`.holds`); rows that share nothing swap at once (`.leaves`); a change that buds a bubble keeps the picture of the old row for the `grow` duration, then the new row with its round cover fades in (`holdsRowWhileBudding`, `Island/IslandSurfaceView.swift` `holdWhileBudding`). After a close the closed row and the black wait `landing` for the island to land; a page opening straight from the launcher gets its black at once.
- **Path morphs:** Core Animation morphs a path element by element, so every outline of one shape has the same element list, and a missing bubble is a circle of no size (`IslandMotion.morphPath`); subpaths that may overlap mid-morph wind the same way, or the nonzero rule cuts a hole (`IslandSilhouette.bubbleWinding`). Harness: `Tests/notchcast-island-motion-test.swift`.

## 11. Light/dark

- Dark is the design; Light is the same geometry with ink inverted (`docs/ui.md:19-21`). `AppCore.applyAppearance()` is the only appearance assignment (`AppCore.swift:799-801`); `.system` → `nil`.
- Every colour through `ramp`/`adaptive`; a few stay fixed on purpose (gradient masks, saturated tiles, selected compact glyph) (`docs/ui.md:40`; `Theme.swift:447-450`).
- Glass adapts on its own. Test over a light wallpaper; dark wallpaper hides transparency and corner bugs (`docs/ui.md:45`).
- **The island is the one surface that does not theme:** it is the hardware notch's black in every appearance (`NotchcastTheme.Colors.surface`, `Island/NotchcastTheme.swift:134-149`), so its ink is the ramp's dark side (`textPrimary/Secondary/Tertiary` 1.0 / 0.60 / 0.40 white) and colour is only `destructive` and `warning` on a glyph. The launcher grown from it keeps its glass and themes as the palette does. Contrast on black: 0.60 white is 7.4:1, 0.40 is 3.7:1 (below AA for text; the island draws no text in tertiary).

## 12. Accessibility

- Rule: every custom control carries a label and traits (`docs/standards.md:236-240`).
- Canonical: compact bar button `.accessibilityLabel(command.name)`, `.accessibilityAddTraits(selected ? [.isSelected] : [])`, `.accessibilityHidden(!revealed)`, decorative glyph hidden (`CompactBar.swift:90-92`, `:123`); cancelable HUD `.accessibilityLabel("Cancel \(message)")` (`MessageHUDView.swift:26`); Settings segment `.accessibilityAddTraits(selected ? [.isSelected] : [])` (`GeneralSettingsView.swift:216`); Notes switcher exposes rename/trash as VoiceOver actions and hides hover buttons (`docs/ui.md:350-351`).
- Keyboard: ↵ primary, Esc cancel, Cancel leading; ⌘↵ in multiline forms; keycaps never printed on buttons, revealed in a hover `Tooltip` (`docs/ui.md:59-60`).
- Reduce Motion: read `@Environment(\.accessibilityReduceMotion)` and return `nil` animations for movement (`CompactBar.swift:45`, `:126-135`); AppKit side `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (`Tinycast/Features/Notes/UI/NotesCoordinator.swift:383`).
- Disabled = dimmed 0.45 as well as disabled (`SettingsComponents.swift:186-188`, `ModalActionButtonStyle.swift:31`).
- **One key map per surface, read from the physical key** (`Pages/IslandKey.swift`): ⌘P pin, ⌘R refresh, ⌘1–9 pages (ASCII layout under ⌘, number-row key codes), Esc close, ↵ activate, ←/→ and Tab/⇧Tab headers, ↑/↓ selection; a held chord or repeat is swallowed so one press acts once. The map is a pure function with a harness (`Tests/notchcast-island-keys-test.swift`), and the views never read `NSEvent` themselves.
- **What the island tells VoiceOver:** a Home row is one element with its action as an accessibility action (`Pages/IslandHomeView.swift:77-79`), a music row reads the title and the artist as its value (`Island/IslandPieces.swift:352-354`), a cancelable message is "Cancel …" (`:240`); the camera band, the level bars, the spinner and the outgoing snapshot are hidden (`Island/IslandClosedView.swift:35`, `IslandSurfaceView.swift:65`); the header's page buttons carry `.isSelected`. Reduce Motion on the AppKit side (`NSWorkspace…accessibilityDisplayShouldReduceMotion`, `Island/IslandPanel.swift:219`) lands the outline at once and only fades content (`IslandMotion.choice`).
- **Not handled anywhere (upstream included):** Increase Contrast and Reduce Transparency; a grep of `Tinycast/` finds no reader. The skill's high-contrast and forced-colours modes have no counterpart here; note it, do not invent one.

## 13. New feature checklist (≤15)

1. Pick the nearest model in §0 and copy its panel recipe (`CameraPanel` for key-taking, `HUDPanel` for readouts); conform to `AnimatedPanel` and call `followMotion()`.
2. Root view: content → `GlassEffectView()` → one continuous clip, last; no scrim, no extra shadow, no border stroke.
3. Wrap every `NSHostingView` root in `.motionScope()`; any movement animation also returns `nil` under Reduce Motion.
4. Read sizes from `@Environment(\.metrics)` on scaled surfaces; add any new number as a `Theme` token (notch geometry belongs in a Notchcast-owned token group, not in a view).
5. Colours only from `Theme.Colors` (`ramp`/`adaptive`); never `Color.white.opacity`, `.gray`, or an opaque fill.
6. Glyphs via `SymbolImage` with the token slot size; dialog icon = the subject's glyph.
7. Controls: `BarButton` in bars, `.modalAction(role)` on panels, `.frosted(in: Capsule())` for floating groups; continuous corners only.
8. Lists: the `AppRow` grammar, the selection→hover→clear fill, `armedHover`, `SectionHeader`.
9. Menus: `PopoverMenu` in-window; never `.contextMenu`, `NSMenu`, `NSAlert` or a system popover.
10. Questions/failures through `DialogController`; status through `AppCore.showMessage`/`showProgress`.
11. Hover labels: `.tooltip` in non-activating panels, `.help()` only in Settings.
12. Keys: ↵ primary, Esc cancel in `sendEvent`; Cancel leading; caps shown only in a hover tooltip.
13. Settings: grouped `Form`, master switch first, `SettingsRowTitle` + one-line subtitle, `.settingsEnabled`, anchor + `SettingsSearchCatalog` entry + `SettingsFileKey`.
14. Copy: Title Case commands/buttons/outcomes, questions for confirmations, sentence case toggles, all strings localized into all eight languages.
15. Accessibility label + traits on every custom control; check Dark and Light over a light wallpaper.

## 14. Anti-patterns seen in code (do not copy)

- **`.help()` inside the palette.** `SectionHeader` (`Tinycast/Features/Launcher/UI/SectionHeader.swift:22`) and the compact bar buttons (`Tinycast/Features/Launcher/UI/CompactBar.swift:89`) use `.help()`, which `docs/ui.md:61` says never shows behind the non-activating panel. Use `.tooltip`.
- **Palette rows without accessibility labels.** `AppRow` (`LauncherList.swift:285-383`) has no `accessibilityLabel`/traits despite `docs/standards.md:238-240`. Give notch rows explicit ones.
- **Magic numbers in views.** The running-app dot is `3×3` with `offset(y: 3)` (`LauncherList.swift:319-322`); HUD glow constants are private literals (`MessageHUDView.swift:9-11`); disabled opacity `0.45` is repeated (`SettingsComponents.swift:187`, `ModalActionButtonStyle.swift:31`); sidebar tile tint `0.1` (`SettingsComponents.swift:24`). Add tokens instead.
- **Capitalization drift.** "Show in menu bar" (`GeneralSettingsView.swift:33`) vs "Show in Menu Bar" (`NotesSettingsView.swift:30`); "Show animations" vs "Show Formatting Bar" (`NotesSettingsView.swift:26`); HUD "Trash Emptied" vs "Copied path". Recommended: sentence case for Settings rows, Title Case for commands/buttons/HUD outcomes.
- **Fixed font sizes outside the two documented exceptions.** `composerSymbol/composerSend/composerStop` are hard 13/13/10pt (`Theme.swift:401-403`); keep new type on text styles.
- **Comment contradicting code.** `HUDPanel` says neither HUD "carries elevation" yet sets `hasShadow = true` (`Tinycast/Windows/HUD/HUDPanel.swift:13-14`).
- **Doc drift (trust code):** ui.md says Notes titlebar 44pt; code has `noteTitlebar 52` (`Theme.swift:82`). ui.md names `Palette/HoverArming.swift`; the file is `Tinycast/Palette/ArmedHover.swift`. ui.md says Camera takes "the same recipe" as the dialog (`panel 26`); `CameraView` clips at `dialog 20` (`CameraView.swift:16`).
- **Editing `EdgeDissolve.swift`/`ThinScrollbar.swift`**, or adding anything to `DesignSystem/`/`Theme` for an Extensions-style opaque feature; both are explicit upstream non-negotiables (`AGENTS.md`).
- **A rule applied past its surface.** "One glyph size per surface" put the menu row's 14 pt mark in the island's 20 pt slot; beside a 17 pt value on the notch it read thin, and the review set 16 (`NotchcastTheme.Pill.symbol`). A component token may depart from the semantic one when the surface's own content says so; write the reason beside it.
- **Out-levelling instead of giving way.** The covered launcher had two fixes on the table, lifting the palette above the island while grown or fading the island's black under the glass; the fade won, as it keeps every window level as upstream set it (§8).
- **A spring with bounce on a shape that meets an edge.** The capsule spring's undershoot showed the screen behind the notch (§10).
- **A second SwiftUI tree for a crossfade.** The outgoing row is a snapshot image, not a second hosted view (`IslandSurfaceView.swift:36`); the frame-by-frame review of two live trees showed the row doubled.
- **Width tokens for pages.** Each open page is as wide as its own content; a shared page width made every page the widest page's width (`NotchcastTheme.Open`, look-decisions 3 Nov).

## 15. Token tiers and governance

The skill's one transferable idea is the three tiers: primitives → semantic → component, each referencing the tier above, named by purpose, changed as an API. Mapped onto this fork:

| Tier | Where | Rule |
| --- | --- | --- |
| Primitive | `Theme.Spacing/Size/Radius/Duration` numbers, the ramp function, the fixed hues (`Theme.swift`) | upstream's; a fork never adds one (hot file, `hotspots.md`) |
| Semantic | `Theme.Colors.selection/rowHover/textSecondary…`, `Theme.Typography.rowTitle/bar…`, `Theme.CompactBarMotion` | upstream's; read through `@Environment(\.metrics)` on scaled surfaces |
| Component | `NotchcastTheme` (`Island/NotchcastTheme.swift`): `Pill`, `Card`, `MusicBars`, `Open`, `Launcher`, `Typography`, `Colors`, `Motion` | every value is an alias or an arithmetic of a semantic token (`rowHeight = Theme.Size.headerHeight`, `symbol = menuIcon * 0.8`); a bare number appears only where no Tinycast value exists (`monitorPill` 180, `textLimit` 196, `minimumWing` 44, the bars' geometry) and names its source in the comment |

Naming stays Swift's: `camelCase` members in nested `enum`s by surface (`Pill.gap`), not the skill's kebab-case `[category]-[property]-[variant]-[state]`; the tier shows in the path (`Theme.Colors.controlHover` → `NotchcastTheme.Colors.controlHover`).

Governance, the skill's propose → review → test → deprecate → remove, as it runs here:

- **Propose:** a new component value is a line in the kit with a one-line comment naming its source (a Tinycast token, a look decision with its date, or Damian's call). No value in a view: `notchcast/check-kit.py` refuses a literal, a raw colour or a fixed font in `Island/` and `Pages/`, and the baseline (`check-kit-baseline.json`) only shrinks.
- **Review:** the footprint diff (`git diff --stat upstream/main...HEAD`) shows zero upstream files for a token change; a value that needs `Theme.swift` is the wrong value.
- **Test:** the catalogue (§17) renders every state in both shapes and both appearances; a token change shows as a pixel diff in the stills and a frame diff on the stage.
- **Deprecate:** keep the old reader, re-expressed through the new value, so producers compile (`IslandActivity.progress`/`endDate` read `value`); remove when no caller is left. No semver: the fork rebases onto every upstream commit, so a token's version is the sha.
- **Validate:** no circular references by construction (the kit only points up); contrast by the ramp table in §11; naming by code review.

Not adopted: a JSON token file with Style Dictionary output. Tinycast's tokens are Swift and the kit reads them directly; a generated layer would be a second source of truth to drift.

## 16. The island kit as the component tier

The skill's component chapter (compound, polymorphic, slot, headless, variants) is React. The native equivalents the island uses, so a new island or page piece follows the same grammar:

- **One set of pieces, every state** (`Island/IslandPieces.swift`): `IslandGlyph` (tone `plain/danger/warning`), `IslandSpinner`, `IslandValueView`, `IslandWord`, `IslandArtwork`, `IslandTrackText`/`IslandScrollingText`, `IslandLevelBars`, `IslandMessageLine`, `IslandActionButton`, and the two lines `IslandActivityLine` (parts `glyph/value/row/card`) and `IslandMusicLine` (`artwork/bars/row/bubble`). A state chooses which parts go where (wings, the row under the camera, the capsule, the bubble); it never restyles a piece. That is the skill's "variant" axis: the part, not a size prop.
- **Environment instead of context:** `@Environment(\.metrics)` for scale, `@Environment(\.hasHardwareNotch)` (`Island/IslandClosedView.swift:4`, set once in `Island/IslandPanel.swift:116,133`) for the camera; a page insets itself by `openShoulder` beside a camera and the header adds the shoulder itself (`Pages/IslandHeaderView.swift:64`). No piece asks the panel.
- **Slots are modifiers and styles:** `BarButton` in the header, `.modalAction` on panels, `armedHover` on rows, `.tooltip` for hover text; a card's button is the footer's bar button held `Spacing.md` inside a row-high capsule with a `Spacing.xs` end so the two ends are concentric (`NotchcastTheme.Card`).
- **Headless = pure decisions with harnesses:** `IslandGeometry` (frames, `panelIndex`), `IslandMotion` (choice, handover, morph path), `IslandSilhouette` (path), `IslandKey` (keys), `IslandClosedState` (what shows). Views read them; harnesses test them without a window (`Tests/notchcast-island-*-test.swift`).
- **The value slot is a sum type** (`IslandActivity.Value`: `timeLeft`, `elapsed`, `percent`, `count`, `step`, `number`, `onOff`, `spinner`), so a producer says what it has and the piece decides how it reads; `onOff(false)` shows Tinycast's own "Off" word, never a second glyph.
- **Metrics the island shares with the launcher** (so a closed row is the launcher's search row and Home is a launcher list): row 36 (`headerHeight`), icon 26 (`resultRowIcon`), icon→text 8 (`md`), pieces 10 (`lg`), inset 12 (`xl`, the HUD pill's), fill corner 10 (`Radius.row`), pitch 38, open corner 26 (`Radius.panel`), glyph slot 20 (`menuIcon`) with a 16 mark, open row glyph `resultRowIcon * 0.7`.

Island checklist, on top of §13: (a) every size, colour, font and duration from `NotchcastTheme` or `Theme`, `check-kit.py` clean; (b) a new piece renders in the capsule, the wings, the row under the camera and the bubble, and the gallery has a page per state in both shapes; (c) a new transition names its handover case and its Reduce Motion path, and the stage replays it; (d) a new key goes into `IslandKey` with a harness line; (e) VoiceOver: one element per row, actions as accessibility actions, decoration hidden; (f) nothing above the island's level, nothing under the launcher's glass but the island's black.

## 17. Catalogue and checks

The skill's Storybook is the offscreen gallery (`notchcast/gallery/`), DEBUG only:

- **Stills:** `snap.sh [--out <empty dir>] [--app <Debug.app>]` renders every gallery page (169 at 14d5c2b6: closed states × 2 shapes, Home and Day, the launcher opening start/mid/end, Dark and Light launcher, the visualizer comparison) with SAME-DATA sample content, then `check-layout.py` (measured accessibility frames: overlap, grid, clipping; 60 known upstream settings and launcher findings, none from the island) and `check-pixels.swift` (the surface against its canvas). The README in that folder has the build wrapper and scratch variables.
- **Motion:** `stage.sh` runs `GalleryStage` (`Gallery/GalleryStage.swift`, `NOTCHCAST_STAGE`) through 15 scenarios at 25 fps with the surface's own curves and writes frames per scenario; read the frames, the PASS line is not a look. The stage replays fades with its own formulas, so a cosmetic it cannot show needs a live run.
- **Code:** `check-kit.py` (no literals in island and page views), `check-feature-shape.py`, `design-check.sh` (ai-design-check with baseline), `lint.sh`, the harnesses under `Tests/notchcast-island-*`, and `Model purity` grep.
- **Review page for Damian:** stills and GIFs of the same scenario on two branches, one decision per change (`show` skill, `decisions` block); the v2→v3 review ran 23 decisions that way.

## 18. From `design-system-patterns`: what does not apply

Read whole; most of it is a React and CSS toolkit. Kept out on purpose:

- CSS custom properties, `data-theme` attributes, a React `ThemeProvider`, localStorage persistence and FOUC scripts: here appearance is one AppKit assignment (`AppCore.applyAppearance()`) and the ramp.
- Multi-brand theming: one brand, Tinycast's; the fork rebrands only what is visible and never carries another app's name.
- CVA variants, polymorphic `as`, `asChild` slots, render props: SwiftUI composes with views, modifiers, styles and environment (§16).
- Figma sync, Style Dictionary, a token JSON, semver on tokens: no second source of truth beside `Theme.swift`.
- Shadow and opacity scales: glass carries its own elevation (no hand-tuned shadow, §4); the island is flat black.
- `prefers-reduced-motion: 0ms`: the island does not zero durations, it lands the outline and keeps the content fades (§12), and activity indicators keep running (§10).
- Contrast gate as code: the ramp has four stops; their ratios are a table (§11), not a CI step.

What it did add, in one line each: the three tiers made explicit with a rule per tier (§15); a window-level table as the z-scale (§8); governance written down for a fork that cannot touch its primitives (§15); the catalogue named as the test of every token change (§17).
