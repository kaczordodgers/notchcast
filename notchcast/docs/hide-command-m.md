# Hide with ⌘M

Settings › Notchcast enables this feature by default, independently of the island.
It uses the shared EventTapHub and the existing Accessibility grant.

## Invariants

- Plain physical ⌘M hides the front app; other modifier combinations pass through.
- Notchcast's own windows retain normal ⌘M handling.
- Repeats and key-up follow the initial key-down decision, even after focus changes.
- Finder without an on-screen normal-layer window retains normal ⌘M handling.
- Window inspection and hiding run on the main actor, outside the synchronous tap.
  Finder's empty-desktop shortcut is replayed as a tagged key pair to its original process.
- Queued actions validate the module generation and frontmost process before acting.
- Switching off unregisters the consumer and clears its key state.

The pure policy harness is `Tests/notchcast-hide-command-m-test.swift`.
Behavior follows an earlier tool; no third-party code is used.
