# Feature descriptors

A feature describes itself once, in the folder that holds its code: `<Name>Descriptor.swift` there holds one `static let <name>` of `NotchcastFeature.Descriptor` with title, subtitle, group, `defaultEnabled`, dependencies, required grants, `isSystemFeature` and `isSystemTweak`. Every field is stated; none has a default. The hub adds one line, `.<name>: .<name>,`, to `descriptors` in `Tinycast/Features/Notchcast/Core/NotchcastFeature+Descriptor.swift` (`merge=union`), and the feature keeps only its enum case in `NotchcastFeature.swift`, with no switch arm.

The folder may sit at any depth under `Tinycast/Features/` (`Launcher/CopyPath/`, `Notchcast/Island/`), beside the feature's `Model/`, `Service/`, `UI/` and `Settings/` folders, never inside them: harnesses compile `Model/` and `Service/` without the hub. Never in `Notchcast/Core/` or the `Notchcast/` root, and never in an upstream folder (a new file there is an upstream file).

`needsIsland` is not a field: it is `dependencies.contains(.island)`, so the two cannot disagree. A feature that shows only in the island lists `.island` first in `dependencies`.

## Features still on the switches

Each `NotchcastFeature.swift` switch starts with one fallback line, `if let descriptor { return descriptor.<field> }` (or `descriptor?.<field> ?? <value>`), and keeps arms only for:

- the capture module (`colorPicker`, `screenshot`, `scrollingCapture`, `recording`, `captureTrimmer`, `captureEditor`) and Treadmill (`treadmillWalk`, `treadmillHistory`): kept out of this batch;
- `switcherQuitKey`: its only code is `Notchcast/Service/AppCore+SwitcherQuitKey.swift`, a `Service/` folder the `nc-Notchcast-*` harnesses compile without the hub; it moves when F2 gives it a folder;
- `editorSpellChecking`: its only code is a patched line in upstream `Notes/`; it moves when it has a fork folder.

`settingsGroup`, `title` and `subtitle` therefore still end in a `default: preconditionFailure(...)` the checker keeps unreachable. `NotchcastFeature.unwired` and `systemToolsSettingsFeatures` are lists, not switches: switch paths and settings rows move in a later batch.

## Checks

`python3 notchcast/check-feature-shape.py` refuses:

- an arm in any `NotchcastFeature.swift` switch for a feature listed in `descriptors`;
- a descriptor declared (`extension NotchcastFeature.Descriptor`, `Descriptor(`, `Descriptor.init(`, or a typed `static let x: Descriptor`) anywhere but a `<Name>Descriptor.swift` in an allowed folder, including the hub file;
- a `*Descriptor.swift` that does not hold exactly the one descriptor it is named for;
- a hub line that maps a feature to another feature's descriptor;
- a feature with neither a descriptor nor an arm in `settingsGroup`, `title` and `subtitle`.

It cannot tell whether the folder is the feature's own; review that. Harnesses that compile `NotchcastFeature.swift` receive the hub file and every descriptor from `notchcast/command-harness-sources.sh`, so adding a descriptor edits no harness header; `land.sh` typechecks the same set:

```sh
swiftc -swift-version 6 -warnings-as-errors -typecheck Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift \
    $(find Tinycast/Features -mindepth 2 -name '*Descriptor.swift' -not -path 'Tinycast/Features/Notchcast/Core/*')
```

`NotchcastFeature*.swift` alone no longer typechecks: the hub list names every descriptor.

## Moving a feature

Record every feature's values on the base (`title`, `subtitle`, `settingsGroup`, `needsIsland`, `defaultEnabled`, `dependencies`, `requiredGrants`, `isSystemFeature`, `isSystemTweak`, `isWired`), write each descriptor with the value that applied (its arm, or the default and the system-feature guards), delete every arm of the moved features, add the hub lines, and diff the same values after. Strings keep their localization keys and tables, so the catalog does not change. Settings rows, backup keys, command lists and switch paths move to descriptors in a later batch.
