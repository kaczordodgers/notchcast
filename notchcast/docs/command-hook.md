# Launcher commands

Define a `NotchcastCommand` beside its feature, then add one array element in
`NotchcastCommandCatalog.all`:

```swift
IslandController.launcherCommand,
```

The value takes `slug`, localized `name`, `sfSymbol`, optional `owner` (default
`.notchcast`), an `isEnabled` main-actor closure and a main-actor `run` closure.
The stable ID is `command:nc-<slug>`. Slugs must be unique and URL path safe.
Execution dismisses the palette, checks availability and runs synchronously.

Catalog entries flow into `CommandCatalog.entries(ownedBy:)`, so the existing
Notchcast `FeatureCommandsSection` renders alias, shortcut and visibility controls.
Shortcuts use a typed `HotKeyAction.notchcastCommand` and the ordinary binding store.
Feature availability also gates hotkey execution. Refresh the index when availability
changes through `AppIndex.refreshNotchcastCommands()`.

Toggle Island uses `legacyID: "command:toggle-island"` for its entry, retaining
ranking, aliases, visibility, favorites and `hotkey.command:toggle-island` bindings.
Its command value also resolves `command:nc-toggle-island`.

Ordinary command deep links use `notchcast://command/nc-<slug>` and ask for consent
like system actions. Only the legacy `notchcast://command/toggle-island` link skips
consent when it carries no input. Hotkeys and launcher execution do not ask.
The shorter `/command/<slug>` spelling is deferred: resolving it needs a catalog
dependency in the pure deep-link parser. Toggle Island's legacy link still works.

`NotchcastLauncher.open()` intentionally remains without a caller. Global shortcuts
already use upstream `togglePalette`; any new island action needs a design decision.

`notchcast-commands-test` compiles the shipped catalog, registration and hotkey mapping.
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
Host filtering uses `ProcessInfo.processInfo.hostName`. Missing or invalid profiles are empty;
no executable or credentials are compiled in. Run Host Command asks which configured entry
to run, and List Commands reports the filtered titles. Arguments are passed directly to the
process without a shell. Command deep links retain the ordinary consent gate.
