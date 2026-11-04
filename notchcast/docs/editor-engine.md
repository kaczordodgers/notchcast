# Document editor engine

The fork document mode edits `.md`/`.markdown` and `.txt`/`.text` files independently of
the Notes folder. This phase supplies the engine and three automatic Notchcast settings rows;
it adds no document window, launcher command, file association or default-handler change.

## Invariants

- `NotchcastCore.editor` owns one session per canonical file URL, including concurrent opens.
- Markdown starts editable. Plain text starts with Markdown rendering off. Formatting plans and
  `NoteEditorInput` reuse Notes' shipped model; Notes' folder repository remains unchanged.
- File coordination and byte IO leave the main actor. Autosave debounces for 300 ms and retains
  edits made during a save. Stopping a module cancels observation and autosave, preserving drafts
  in memory; closing a dirty session requires explicit discard or a successful flush.
- Saves compare the current file bytes with the exact version last read inside the coordinated
  write. External changes retain both versions; deletion retains the draft and requires Save As.
  Save My Changes also compares against the external version presented for that decision, so a
  second external change cannot be overwritten silently. Non-coordinating writers can still race
  the write, as with Apple's document coordination generally.
- Failed quit saves write the current draft as UTF-8 under the channel’s Application Support
  `EditorRecovery` directory and log its path. Replacements preserve destination metadata.
- UTF-8, UTF-8 BOM, BOM-marked UTF-16 LE/BE and Windows-1250 are read and saved without loss.
  Unmodified saves do not write. Line endings, NUL, normalization and BOM bytes are preserved.
  Unrepresentable edits fail without changing the file. Save As claims a new file without replacing
  an existing destination.
- `NSFilePresenter` observes external replacements and deletion. The harness verifies consecutive
  atomic replacements on temporary files. A moved file retains its old destination and reports
  deletion rather than silently redirecting later saves.
- Word counts use `NLTokenizer(.word)`, characters exclude newline graphemes, and lines count CRLF
  once. Brain Dump accepts growth and changes to trailing whitespace, rejecting other deletions.

## Actions and settings

`EditorCoordinator` exposes `open`, `newDocument`, `saveAs`, `close` and `flush` functions.
Sessions expose draft editing, Notes formatting plans, refresh, save, conflict resolution, dirty
state, errors, editor input, Brain Dump and Stay on Top state. Surfaces must route Save As through
the coordinator to enforce the destination's feature switch, and display failures with upstream's
dialogs/HUDs. A failed save never means a successful close.

Markdown Files and Plain Text Files control their sessions independently of the island. Editor
Spell Checking defaults on and applies when Notes creates its text view; document surfaces read
`NotchcastPreferences.shared.isOn(.editorSpellChecking)`. Font (`jetBrainsMono`), theme (`githubDark`) and pairing preferences
are persisted in a bundle-scoped fork store. This phase does not apply font or color styling.

## Left for the look

The document window using `NoteEditorView`/`NoteTextView`, Open/Save panels, conflict/deletion dialogs,
live application of preferences, font/theme controls, statistics, centered columns, Stay on Top and
Brain Dump controls remain for the visual phase. OS document registration/open events belong with
that window. Mermaid, a preview pane, rich text and printing remain outside this scope.

## Verification

`./Scripts/run-tests.sh nc-DocumentEditor-document-test` covers encoding, revision checks, Save As,
deletion, conflict decisions, autosave, the real presenter, Notes edit plans, counts and preferences.
`./Scripts/run-tests.sh nc-DocumentEditor-coordinator-test` covers lifecycle, concurrent opens,
symlink identity, feature switches, cancellation and dirty-close protection.
Both use isolated preferences and temporary directories; neither opens a document window.
