# Launcher commands

A new feature appends one case line in `Core/NotchcastFeature.swift` and describes itself in its
own folder, never with switch arms: see [feature-descriptors.md](feature-descriptors.md). The
switches keep one arm per line for the few features listed there; never extend an existing line
or combine switch arms.
New groups append one case line in `Core/NotchcastFeature+SettingsGroup.swift`, inside the
separator comments. Keep separators between cases and members and between switches.
Both files use `merge=union`; run `python3 notchcast/check-feature-shape.py` and
`python3 notchcast/check-feature-shape-test.py` after merging.
The checker rejects repeated enum cases and repeated feature cases within a switch: union
can retain both the old and edited arm when another branch appends nearby.

Modules register in `Core/NotchcastCore+Modules.swift`: one `static let` line and one entry
line each. Settings search anchors and rows live one per line in
`Settings/NotchcastSettingsSearch.swift`. Both files use `merge=union`; the same checker
rejects an entry split over lines, a repeated `static` name, a module registered twice and
a search row whose anchor and title repeat. It cannot tell a renamed module or a retitled
row from a new one: after a merge, check that an edited line did not come back beside its edit.

Settings in `Core/NotchcastPreferences.swift`: one stored property per line (with its `didSet`)
and one init assignment per line; nested types and helpers go in the extension below the class.
The file uses `merge=union`; the checker rejects a split setting or statement, a repeated
setting and a repeated assignment.

Define a `NotchcastCommand` beside its feature, then add one array element in
`Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift`:

```swift
IslandController.launcherCommand,
```

Register each feature on one line with a trailing comma and no other content on that line.
Registration requires no changes in Tests. Git uses `merge=union` for this file so
concurrent registrations merge cleanly. After every merge, check the file by hand:
union merging can keep the same registration twice, and it keeps both the old and the
new line when one branch removes or edits a registration while another adds one, so a
removed command can come back.
`notchcast/check-legacy-command-ids.py` guards Toggle Island's persisted legacy ID in its real source before the CI Debug build; change it only with a migration.

The value takes `slug`, localized `name`, `sfSymbol`, optional `owner` (default
`.notchcast`), an `isEnabled` main-actor closure and a main-actor `run` closure.
The stable ID is `command:nc-<slug>`. Slugs must be unique and URL path safe.
Execution dismisses the palette, checks availability and runs synchronously.

Each module page in Notchcast settings lists its feature's commands as `FeatureCommandRow`s,
which render alias, shortcut and visibility controls.
Shortcuts use a typed `HotKeyAction.notchcastCommand` and the ordinary binding store.
Feature availability also gates hotkey execution. A combo registers with Carbon only while its feature switch and that switch's dependencies are on (`NotchcastCommandCatalog.registersHotKey`), so a switched-off feature gives its combos back to the system. The saved binding still reserves its combo and modifier in conflict detection while releasing its Carbon registration and modifier tap. On every availability change, `commandAvailabilityChanged` refreshes the index through `AppIndex.refreshNotchcastCommands()` and re-registers hotkeys through `HotKeyManager.syncNotchcastCommands()`.

BatteryModule owns `nc-keep-awake`, which pauses or resumes its assertion without changing
the Keep Awake switch. FanControl owns `nc-fans-max` and `nc-fans-auto`; these update the
same fan-mode preference as Settings and require both System Monitor and Fan Control.
Changes to these feature switches refresh the command index through NotchcastPreferences.

Toggle Island uses `legacyID: "command:toggle-island"` for its entry, retaining
ranking, aliases, visibility, favorites and `hotkey.command:toggle-island` bindings.
Its command value also resolves `command:nc-toggle-island`.

Ordinary command deep links use `notchcast://command/nc-<slug>` and ask for consent
like system actions. Only the legacy `notchcast://command/toggle-island` link skips
consent when it carries no input. Hotkeys and launcher execution do not ask.

Page commands live beside `IslandPage`, with one catalog line per page. `island-home`
and `island-day` open the requested page with key focus, including Home without live
activities. Both require the island; Day also requires calendar, weather or markets. Preference
changes refresh command availability in the index.

A command that opens a palette screen (Theme) sets `keepsPalette`. The launcher then stays up and
pushes the screen, so Escape steps back to the results and the island does not replay its opening.
Every other command hides the palette before it runs.

The launcher shows upstream's Settings, About and Quit rows under the Notchcast name
(`AppEntry+NotchcastCommands.swift`); the Tinycast names stay alternate titles for search.
The shorter `/command/<slug>` spelling is deferred: resolving it needs a catalog
dependency in the pure deep-link parser. Toggle Island's legacy link still works.

`NotchcastLauncher.open()` intentionally remains without a caller. Global shortcuts
already use upstream `togglePalette`; any new island action needs a design decision.

`notchcast-commands-test` compiles the shipped catalog logic and hotkey mapping with
its own test commands in an extension. It excludes `NotchcastCommandCatalog+All.swift`
and feature command sources, so new registrations require no test changes.
The three upstream index/settings/hotkey harnesses use empty fork-catalog fixtures through
one compiler-source hook; no harness registration is added to the upstream runner.
`Scripts/run-tests.sh` sources `notchcast/command-harness-sources.sh` because upstream
harnesses compiling hooked files need the fork types those hooks reference. Any new
upstream harness compiling CommandCatalog, AppIndex or HotKey files must use
`command-harness-sources.sh` to include the appropriate fork fixture sources.

The tools commands register Convert Files, Compress Video, Make GIF, Compress Image,
Resize Image, Extract Text, Run Host Command and List Commands. Each follows its own
Convert Files, Media Tools or Command Runner switch. Convert Files additionally requires
Downloads to be on; it reports that requirement and attaches to the Downloads queue owner.
Conversion targets and resize dimensions use the existing choice dialog. File input is
Finder's selection, never clipboard file URLs. Completion and input errors use island status
messages. Quick Add Task retains its engine but has no launcher registration or live client.

Host commands are read at use from `Notchcast/host-commands.json` under Application Support.
The JSON is an array of entries with `id`, `title`, absolute `executable`, `arguments` (array),
`hosts` (array; empty allows every host) and `workingDirectory` (optional string).
Host filtering resolves `gethostname` off the main actor. Missing or invalid profiles are empty;
no executable or credentials are compiled in. Run Host Command asks which configured entry
to run, and List Commands reports the filtered titles. Arguments are passed directly to the
process without a shell. Command deep links retain the ordinary consent gate.
