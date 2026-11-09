# Feature descriptors

A feature describes itself once, in its own folder: `Tinycast/Features/<Folder>/<Name>Descriptor.swift` holds one `static let <name>` of `NotchcastFeature.Descriptor` with title, subtitle, group, `needsIsland`, `defaultEnabled`, dependencies and required grants. Every field is stated; none has a default. The hub adds one line, `.<name>: .<name>,`, to `descriptors` in `Tinycast/Features/Notchcast/Core/NotchcastFeature+Descriptor.swift` (`merge=union`), and the feature keeps only its enum case in `NotchcastFeature.swift`, with no switch arm.

Until every feature moves, each switch in `NotchcastFeature.swift` starts with one fallback line, `if let descriptor { return descriptor.<field> }`: described features answer from their descriptor, the rest from their arms. `settingsGroup`, `title` and `subtitle` end in a `default:` the checker keeps unreachable. `settingsGroup` stays because `needsIsland`, `defaultEnabled`, `isSystemFeature` and harnesses read it.

`python3 notchcast/check-feature-shape.py` refuses:

- an arm in any `NotchcastFeature.swift` switch for a feature listed in `descriptors`;
- a descriptor declared anywhere but the root of a feature folder other than `Notchcast/`, including the hub file and subfolders;
- a `*Descriptor.swift` at a folder root that does not hold exactly the one descriptor it is named for;
- a hub line that maps a feature to another feature's descriptor;
- a feature with neither a descriptor nor an arm in `settingsGroup`, `title` and `subtitle`.

It cannot tell whether the folder is the feature's own; review that. Harnesses that compile `NotchcastFeature.swift` receive the hub file and every `Tinycast/Features/*/*Descriptor.swift` from `notchcast/command-harness-sources.sh`, so adding a descriptor edits no harness header; `land.sh` typechecks the same set.

Moving a batch: record every feature's values on the base (`title`, `subtitle`, `settingsGroup`, `needsIsland`, `defaultEnabled`, `dependencies`, `requiredGrants`, `isSystemFeature`, `isSystemTweak`), write each descriptor with the value that applied (its arm, or the default and the system-feature guards), delete every arm of the moved features, add the hub lines, and diff the same values after. Strings keep their `table: "Notchcast"` keys, so the catalog does not change. Settings rows, backup keys, command lists and switch paths move to descriptors in later batches.

Pilot batch: `hideCommandM`, `lowDiskWarning`, `linkHealth`, `eventReminder`, `linkQuickFixes`.
