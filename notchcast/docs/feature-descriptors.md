# Feature descriptors

A feature describes itself once, in the folder that holds its code: `<Name>Descriptor.swift` there holds one `static let <name>` of `NotchcastFeature.Descriptor` with title, subtitle, group, `defaultEnabled`, dependencies, required grants, `isSystemFeature` and `isSystemTweak`. Every field is stated; none has a default. The hub adds one line, `.<name>: .<name>,`, to `descriptors` in `Tinycast/Features/Notchcast/Core/NotchcastFeature+Descriptor.swift` (`merge=union`), and the feature keeps only its enum case in `NotchcastFeature.swift`, with no switch arm.

The folder may sit at any depth under `Tinycast/Features/` (`Notchcast/Island/`, `MachRemote/Integration/`), beside the feature's `Model/`, `Service/`, `UI/` and `Settings/` folders, never inside them: harnesses compile `Model/` and `Service/` without the hub. The same holds for a flat code folder a harness globs whole: `distillConvert`, `sendFiles` and `updateRemote` are described from `Distill/` and `MachRemote/`, one level above `Distill/Convert/`, `MachRemote/SendFiles/` and `MachRemote/UpdateRemote/`, because five harnesses compile `*.swift` there without the hub. Never in `Notchcast/Core/` or the `Notchcast/` root, and never anywhere under a folder upstream ships (`Launcher/`, `Notes/`, ...): a fork file there fails drift gate 1 (`upstream-folders`), so such a feature moves to a fork folder of its own first.

`needsIsland` is not a field: it is `dependencies.contains(.island)`, so the two cannot disagree. A feature that shows only in the island lists `.island` first in `dependencies`.

## Features still on the switches

`dependencies`, `isSystemFeature` and `isSystemTweak` read only the descriptor (`[]` and `false` without one). `settingsGroup`, `title`, `subtitle`, `requiredGrants` and `defaultEnabled` start with the fallback line `if let descriptor { return descriptor.<field> }` and keep arms only for:

- the capture module (`colorPicker`, `screenshot`, `scrollingCapture`, `recording`, `captureTrimmer`, `captureEditor`) and Treadmill (`treadmillWalk`, `treadmillHistory`): kept out of this batch;
- `switcherQuitKey`: its code is `Notchcast/Model/SwitcherQuitKeyPolicy.swift` and `Notchcast/Service/AppCore+SwitcherQuitKey.swift`, both in layer folders with no feature folder of their own; it moves when F2 gives it one;
- `editorSpellChecking`: its only code is a patched line in upstream `Notes/`; it moves when it has a fork folder;
- the features whose code sits in upstream's `Launcher/` (`githubSearch`, `clearNotifications`, `launcherAnswers`, `copyPath`, `smallCommands`, `launcherNumberKeys`, `launcherAliasSpace`): Phase 2c moves each to a fork folder of its own and describes it there.

`settingsGroup`, `title` and `subtitle` therefore still end in a `default: preconditionFailure(...)` the checker keeps unreachable; the switches go when these seventeen move. `NotchcastFeature.unwired` and `systemToolsSettingsFeatures` are lists, not switches: switch paths and settings rows move in a later batch.

## Checks

`python3 notchcast/check-feature-shape.py` refuses:

- an arm in any `NotchcastFeature.swift` switch for a feature listed in `descriptors`;
- a descriptor declared (`extension NotchcastFeature.Descriptor`, `Descriptor(`, `Descriptor.init(`, or a typed `static let x: Descriptor`) anywhere but a `<Name>Descriptor.swift` in an allowed folder, including the hub file;
- a `*Descriptor.swift` that does not hold exactly the one descriptor it is named for, or whose descriptor the hub does not list;
- a `*Descriptor.swift` under a folder upstream ships at `merge-base HEAD upstream/main` (skipped when there is no `upstream/main` ref; drift gate 1 still refuses it at landing);
- a hub line that maps a feature to another feature's descriptor;
- a feature with neither a descriptor nor an arm in `settingsGroup`, `title` and `subtitle`;
- a `register(_: AppCore)` implementation anywhere but a `<Type>+Registration.swift` in an allowed folder (the descriptor's rules), or under a folder upstream ships;
- a registrant listed twice, or listed while `NotchcastCore+Modules.swift` still holds a `static` of its type or an entry `module: <Type>...`.

It cannot tell whether the folder is the feature's own; review that. Harnesses that compile `NotchcastFeature.swift` receive the hub file and every descriptor from `notchcast/command-harness-sources.sh`, so adding a descriptor edits no harness header; `land.sh` typechecks the same set:

```sh
swiftc -swift-version 6 -warnings-as-errors -typecheck Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift \
    $(find Tinycast/Features -mindepth 2 -name '*Descriptor.swift' -not -path 'Tinycast/Features/Notchcast/Core/*')
```

`NotchcastFeature*.swift` alone no longer typechecks: the hub list names every descriptor.

## Registering a module

A feature owns its module instance and hands the controller its entries; the hub no longer holds a `static let` or an entry for it, and nothing outside the hub reads `NotchcastCore.<module>`. `LowDisk/` and `WaitingAlerts/` are the reference.

1. Beside the descriptor, add `<Module>+Registration.swift` (`Tinycast/Features/LowDisk/LowDiskModule+Registration.swift`):

   ```swift
   extension LowDiskModule: NotchcastRegistrant {
       static let shared = LowDiskModule()

       static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
           [.init(requires: [.island, .lowDiskWarning], module: shared)]
       }
   }
   ```

   Move the hub's initializer into `shared` unchanged, and its `requires`/`requiresAny` into the entry unchanged. A module built from `core` uses `static private(set) var shared: <Module>?`, set in `register`. Start-time glue the hub ran only for this module (a callback, a `configure(core)`) moves into `register`, before `return`. One file may return several entries.
2. Append `<Module>.self,` to `registrants` in `Tinycast/Features/Notchcast/Core/NotchcastCore+Registrants.swift` (`merge=union`), one per line.
3. Delete the module's `static let` and its entry line from `NotchcastCore+Modules.swift`.
4. Rewrite every `NotchcastCore.<module>` to `<Module>.shared`: commands, settings and the feature's other files read the instance it owns (`run: { LowDiskModule.shared.manager.refresh() }`). `stopForTermination` in `NotchcastCore.swift` is the one hub line that may name `<Module>.shared`; keep its order. The module and its registration reach the app only through the host seam `Core/NotchcastHost.swift`, which `NotchcastCore.start` sets before any module starts: `AppCore.shared.showMessage(m, tone: t)` becomes `NotchcastHost.current.showMessage(m, t)`, and `AppCore.shared.appIndex.refreshNotchcastCommands()` becomes `NotchcastHost.current.refreshNotchcastCommands()`. `register(_ core: AppCore)` still receives `core` for glue the seam does not cover.
5. Lower `core-lookups` in `notchcast/drift-baseline.json` for every file you cleaned; drop a key that reaches 0.
6. A harness that stubbed `NotchcastCore.<module>` compiles the real `+Registration.swift`, `Core/NotchcastModule.swift` and `Core/NotchcastRegistrant.swift` through `// notchcast-sources:` instead, and checks the entries `register` returns (`Tests/nc-WaitingAlerts-engine-test.swift`). A harness compiling code that uses the seam adds `Core/NotchcastHost.swift` (plus `enum DialogTone {}`, with the cases the code names, when it lacks the real one) and drops its `AppCore` stub; only a harness that calls `register` keeps an empty `final class AppCore {}`. It can set `NotchcastHost.current`'s closures to count messages and refreshes (`Tests/notchcast-system-notice-hookups-test.swift`).

A registration names only its own folder, `Notchcast/Core` kernel types and upstream. Wiring between two fork features (feature A reading feature B's module, such as Shelf's link status reading Mac Link and Link Health) stays in `NotchcastCore.start` as hub glue, so drift gate 1 `boundaries` never rises; such a module moves only when that glue can read both sides' `shared`.

Registrant entries start after every hub entry and before the services' entries, so a module that must start before a hub module stays in the hub until that one moves too. Confirm the order before moving one.

## Moving a feature

Record every feature's values on the base (`title`, `subtitle`, `settingsGroup`, `needsIsland`, `defaultEnabled`, `dependencies`, `requiredGrants`, `isSystemFeature`, `isSystemTweak`, `isWired`), write each descriptor with the value that applied (its arm, or the default and the system-feature guards), delete every arm of the moved features, add the hub lines, and diff the same values after. Strings keep their localization keys and tables, so the catalog does not change.

## What stays out of the descriptor

`Descriptor` is plain data that harnesses compile with the hub alone, so anything that needs a view, a module or another feature's types lives beside it in the same folder instead:

- backup keys: `<Name>BackupKeys.swift` beside `<Name>Descriptor.swift`, one `NotchcastFeature.BackupKeys` per described feature, collected by `featureKeys` in the schema ([settings-backup.md](settings-backup.md));
- settings data: the feature's own lists (Tweaks: `Tweaks/Settings/TweakToggle.swift` lists each section's catalog tweaks in order).

Three things stay in the hub on purpose:

- commands stay in `NotchcastCommandCatalog+All.swift`, one line each, each declared on the feature's own type; the catalog checkers and harnesses read that file line by line;
- the per-feature `if`s in `NotchcastModuleSettingsView` and the row views and `NotchcastSettingRows+A`–`D` dispatch files in `Notchcast/Settings/` stay, because they read `NotchcastCore` and moving them into feature folders raises drift gate 1's core-lookups count;
- switch paths.
