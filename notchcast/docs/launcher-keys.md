# Launcher key decisions

Pure synchronous engines; callers supply entry rows in display order, excluding cards,
files, headers and fallback rows. A nil number-key result delegates to the existing
favorite handler. Only digits 1 through 9 are intercepted, only with a nonempty query.
The caller dispatches these after checking the Command chord.
`rowIndex` resolves the actual result or favourite row, including a leading card.

Alias input uses the editor's UTF-16 caret offset and selection length. The caller
gates launcher mode, search focus, composition, menus, control lists and collapsed
state before evaluating Space. Pass all held modifiers as `hasModifiers`. Map entry
kind from `AppEntry.Kind`, never from its ID. An optional-only view opens its search;
other entries with arguments focus the first field, including optional fields.
Duplicate aliases and aliases that prefix a longer space-separated alias leave Space as text.

`LauncherAliasSpaceTrace` records each Space gate and decision at debug level, so nothing is built or
logged until a reader asks: `log stream --level debug --predicate 'category == "AliasSpace"'`.

Both feature switches default off and require no island. No commands are registered.
The previous-screen launcher hotkey toggle is outside this engine pack.

Behavior adapted from AGPL-3.0 sources (the fork's AGPL-3.0 license applies):

- seancxk/tinycast-fork, `patches/0001-alias-space.patch`:
  https://github.com/seancxk/tinycast-fork
- sermelipharo/tinycast-space, `.space/patches/0001-alias-space.patch` and
  `.space/patches/0016-launcher-keys.patch` (ported there from songhyun-k/tinycast):
  https://github.com/sermelipharo/tinycast-space
- Its `.space/patches/0015-alias-tab.patch` was reviewed; Tab remains unchanged.
