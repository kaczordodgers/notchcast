# Dictation status routing

The Notchcast “Dictation in Island” switch routes listening and transcription text through
the existing island progress HUD. Routing requires the island and Status Messages to be on
and an island presenter to be available. Otherwise the upstream capsule stays visible.

The upstream nonactivating panel remains key while routed, positioned beyond every screen's
right edge. Its Return and Escape handlers and the coordinator's session ownership stay intact.
Changing either switch restores the capsule during the same session. Closing dictation dismisses
its progress message without dismissing a replacement message from another feature.
While dictation is active, a foreign message is immediately replaced by the dictation status.

This is text routing only. It adds no island view or audio-level visualization.

Run `./Scripts/run-tests.sh nc-DictationIslandHUD-routing-test` for the pure phase and switch policy.
