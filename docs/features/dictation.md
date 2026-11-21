# Dictation (experimental)

Dictation is off by default. A user-selected global shortcut records from the chosen microphone,
transcribes locally and sends the result through `TextInjector`. Parakeet Ultra (quality) and Redux
(lightweight) support 25 languages. Qwen3-ASR 0.6B and 1.7B support 30 languages and 22 Chinese dialects.
No model is bundled. The Settings pane downloads a pinned Core ML conversion on request.

Recognition uses Apple's Core ML and Accelerate, with no external library. Each model family has
its own adapter inside the bundled helper; both variants share that family's implementation.
The same audio-to-text channel feeds the coordinator regardless of which model is selected.
Parakeet variants declare their joint model, blank token and encoder placement in `DictationModel`, alongside the pinned
download metadata. A new variant must match the adapter's tensor shapes and TDT decoding contract;
sharing a model-family name alone does not establish compatibility.
Redux is the default upstream; Notchcast seeds Ultra once on a profile with no stored model
(`DictationFirstModel`). Redux's encoder uses CPU/GPU to avoid the several-minute initial Neural Engine
compilation of its 2-bit weights; Ultra's encoder and both variants' decoder/joint use CPU/Neural Engine.

## Invariants

- `AppCore` owns the model store and coordinator. The microphone session, panel and focused target
  belong only to `DictationCoordinator`; no recording starts merely by launching Tinycast or opening
  Settings.
- The enable switch is consent. It explains microphone and Accessibility access before enabling,
  and, like every Dictation preference, is excluded from backups so importing settings cannot arm
  a global recording shortcut.
- Microphone status appears in Permissions and the Dictation pane. Neither pane prompts on display;
  only a user action requests access, while revoked access is refreshed from macOS.
- `HotKeyAction.dictation` uses the shared recorder and conflict handling. Toggle mode accepts any
  binding; hold-to-talk accepts a Carbon chord or a single physical modifier, including Globe.
  Modifier holds begin after 250 ms alone and reserve their key across single and double taps.
  Another modifier, key or click cancels the hold without inserting text. Double taps require toggle.
- The Globe key mode needs no recorded shortcut; one that is recorded toggles in it. Released within 300 ms with no other input, a Globe press is a tap: it starts recording, and the next press finishes. Held past 300 ms it records until release. Another key, modifier or click during the press makes it a shortcut instead, and discards a held recording; Return and Escape keep their panel meaning. `DictationMode.GlobeDetector` decides on the events' monotonic timestamps; `NotchcastGlobeTrigger` feeds it from event monitors installed only while Dictation is enabled in this mode, and owns the 300 ms timer. A field's own mic session ignores the Globe key. macOS's own "Press 🌐 key to" action must be set to Do Nothing; the pane says so and opens Keyboard settings.
- Carbon or the shared modifier monitor reports release to stop a held recording. Return finishes,
  Escape cancels. Opening a shortcut recorder cancels a held recording before pausing its shortcuts.
  A session token
  prevents a cancelled or superseded transcription from inserting text later.
- AI Chat's composer mic is always click-to-toggle into that field: `toggle(into:)` targets its
  `ComposerTextView` in process whatever has focus, `field` tells only that button it is running, and
  its transcript is inserted whatever the destination setting, never copied.
  Switching chats or closing the composer cancels only the session targeting that editor, including
  one started by a shortcut. The session token is checked again when queued insertion runs.
- The nonactivating panel preserves the target app. Text insertion reuses `TextInjector`, including
  its temporary clipboard ownership, focus, secure-input and protected-target checks. Copy-only
  writes the plain transcript without reading the caret; paste-and-copy writes the persistent copy
  after delivery or a failed insertion.
- The Liquid Glass capsule displays 21 fixed frequency bands driven by the microphone, sampled at
  most 20 times per second through a reused 512-point Accelerate transform on the capture queue.
  Logarithmic bands span 32–5000 Hz so speech sits nearer the middle. Smoothed levels taper and
  fade only toward the edges, without a center peak or mirroring.
  Transcription replaces them with a smaller wave whose white center fades to gray, moving left to
  right at up to 30 frames per second.
  Reduce Motion pauses the processing timeline; closing the panel releases its hosting view so no
  animation continues while hidden.
- Dictation fades the default output's software volume down by about 90% from shortcut press, or from
  the start cue when Play sounds is on, then restores
  it on completion, cancellation and normal quit. An unsupported output is left untouched, as is a
  volume the user changes during capture. Before each fade step, a bundle-ID Application Support
  file records the device UID, original volume and the values before and after that step.
  Relaunch restores the original device only if its volume still matches that record, including
  when Dictation is disabled. An unavailable device keeps its record for a later attempt; new ducking
  waits for that recovery. File writes run off-main and finish before the hardware changes.
- Play sounds is on by default. When on, macOS's `dt-begin.caf` plays on the microphone's first samples
  and `dt-confirm.caf` when recording stops (release, toggle, Return or the length limit); cancelling
  stays silent. These are internal resources in `AssistantServices.framework`, not bundled audio;
  their location is undocumented, and a missing sound is silently skipped without blocking dictation.
  A Bluetooth headset drops output while it switches to its microphone, sometimes after the first
  samples arrive, so with a Bluetooth microphone the start cue waits half a second more. With sounds
  on, for any microphone, ducking starts with the start cue instead of at the press, and never for a
  session cancelled meanwhile. On stop the volume is restored at once instead of faded, so the cue
  plays at full volume before the microphone closes and a headset switches back. Ducking is device-wide, so
  media at full volume can mask the start cue. Through speakers a cue can reach the recording; it is
  not removed.
- The microphone, waveform, permissions and insertion stay in Tinycast. Model loading, audio
  features and decoding run in `Tinycast Dictation` (`Tinycast Dev Dictation` in Debug), started
  only for transcription. Main-app state never retains Core ML models or imports the adapters.
  The helper is an embedded accessory app with no bundled icon, Dock item or windows.
- Core ML models live under this build's bundle-ID cache. After one minute idle by default, the
  store terminates and reaps the helper, releasing its model memory. Other delays or Never are
  selectable. Switching models reaps the old helper before loading the next; removing a loaded model
  stops its helper before deleting the directory and blocks new requests for that model meanwhile.
  Cancelling an active transcription, failed inference and normal quit stop the helper; late results cannot paste.
- Audio stays in memory, bounded to five minutes of mono 16 kHz Float32 samples. Pipes carry
  bounded JSON control messages and binary audio; recordings are never written to disk or sent
  over the network. Long recordings split near a quiet passage without overlapping samples.
- Live insertion is off by default and flushes at speech pauses, or after eight seconds of
  unpaused speech at the latest. While recording, the coordinator transcribes the audio since the
  last flush and pastes each chunk through `TextInjector` in order; finishing lets queued chunks
  land, then transcribes only the remainder. A cancelled chunk keeps its audio behind for that
  final pass, and a copy destination receives the assembled text. Chunk cuts fall near a
  quiet passage, like long recordings do, and copy-only sessions never start the live loop.
- Every flush re-transcribes from a pause-anchored overlap start and drops the repeated head
  word-wise, tolerating fragment words and case or punctuation variants, so word splits at
  chunk cuts rarely duplicate. When the app exposes no caret, spacing and casing fall back to
  the already pasted text instead of gluing chunks together. A chunk that fails to paste is
  reported once at finish, never silently lost. Pasted text is never revised: matching Siri-style
  correction would mean deleting and retyping inside foreign apps, which is fragile next to a
  moving cursor and the user's own edits.
- Model files download through a feature-private ephemeral session without a disk URL cache.
  Repositories and revisions are explicit in `DictationModel`; each download is staged and
  published only when all required files arrive, their sizes agree with the manifest and large-file
  SHA-256 checksums match. Settings shows combined byte counts and a percentage in a full-width
  progress row for the selected model. Download delegate callbacks report actual transferred bytes,
  with intermediate updates limited to one per 100 ms per file; each verified file reports its final
  count immediately. Progress observation stays in the download row. Switching
  selection leaves its download running in the background. Cancellation and
  normal quit remove staging files without publishing a partial model. A new download removes stale
  staging directories left by a crash or forced quit, without touching installed models or other files.
  A nonblocking file lock covers cleanup through publication, rejecting another download sharing
  the same cache root. Its empty lock file stays in place; macOS releases the lock on process exit.
- An installed Qwen model exposes a language hint; Auto leaves language detection to the model. Parakeet
  does not accept a language hint. Neither adapter exposes user vocabulary. Qwen prepares its fixed
  prompts and supported language hints once, then retains only the tokenizer's decoding tables
  and prepared tokens, not the BPE encoding rules.
- Sharing the model with other apps is off by default and serves only while it and Dictation are both
  on: an OpenAI-compatible `POST /v1/audio/transcriptions` (multipart `file`, `model` ignored,
  optional ISO-639-1 `language`, `response_format` json or text) and `GET /v1/models`, bound to
  127.0.0.1 on a configurable port (8178 by default). `NotchcastCore` owns `DictationServer`, so quitting stops it.
  Clients should call `127.0.0.1`, not `localhost`: a client that tries `::1` first may reach another process there.
- The switch and port live in the fork's `.notchcast` defaults suite, which backups and `settings.json`
  never carry, so an import cannot open a listener. The bearer token is 32 random bytes generated on first
  use, kept only in the Keychain (`KeychainSecretStore.dictationServer`), compared in constant time, never
  logged or shown, and copied to the pasteboard as concealed and current-host only, so Clipboard History
  skips it and Universal Clipboard never carries it. A token that could not be saved leaves the old one
  serving, and Settings says so under the status.
- Every request is decided from its head before any body is read: a Host other than 127.0.0.1 or
  localhost is 403, a missing or wrong token 401, and a Content-Length over 25 MB (plus form overhead)
  413. Chunked uploads are refused; each connection carries one request, at most eight at once (counted
  on the main actor; a ninth is dropped). The head must arrive within 5 seconds and the whole request
  within 30. Reading and parsing run off the main actor; only a decided request comes back to it.
- An upload must start with the bytes of an allowed container (WAV, FLAC, Ogg, MP3, MP4/M4A, WebM),
  whatever its filename, and audio over 60 minutes is 413; both are refused before the request waits
  for the model. A client that closes its connection, or only its sending side, cancels its
  transcription.
- The user's own dictation always wins. Shared requests take the model one at a time in arrival order
  through the add-on transcription runner, and none starts while the user records or transcribes. A
  request still running when the user starts is cancelled and answered 503 with `Retry-After`, and the
  user's session waits only for its cleanup. A missing model is 503.
- An upload is written to a private 0600 temporary file only for decoding and removed when its request ends;
  files a crash left behind are removed when `DictationServer` starts, before any listener.
- The `Model/` folder imports Foundation only. Context-sensitive spaces and capitalization are a
  pure decision driven by text around the caret. Capitalization adapts by default and can be disabled
  without disabling contextual spaces; if an app does not expose that context through
  Accessibility, the plain transcript is inserted without guessing.

## Validation

`DictationCueTests` checks system resource paths, playback ordering and missing sounds without audio output.
`DictationFieldTests` checks composer switching and teardown, scoped cancellation, delayed insertion and
the order of sound cues against ducking
with synthetic capture and real AppKit editors, without recording audio or touching the shared clipboard.
`nc-Dictation-globe-test` checks the Globe tap-or-hold decision on synthetic timestamps.
`DictationTests` checks formatting and model options; `DictationInferenceTests` checks score selection,
byte BPE, Fourier/mel features, listening bands and audio partitioning without downloading a model. `DictationWorkerTests`
exercises framed IPC, worker reuse/switching, removal, cancellation and broken pipes with a fixture.
An in-process URLProtocol fixture checks byte progress before the first file completes, combined
progress and atomic installation for both families, including cancellation, stale staging cleanup
and competing downloads on shared or independent cache roots, without sockets or timed waits.
`DictationVolumeTests` uses private files and injected audio controls to verify crash recovery
before and after fade steps, user volume changes, output switching, failed writes and rapid cancellation,
without changing the system volume or downloading a model.
`nc-DictationSharing-server-test` checks the endpoint's head parsing, host and token checks, size, container
and length caps, multipart forms fed byte by byte, responses, the head and body deadlines, the connection
cap, cancellation when a client leaves, the crash-leftover sweep, and the dictation-wins queue through the
add-on runner with fakes, without a socket, a timer or a model. `nc-DictationSharing-bind-test` starts the
real listener on a free port and checks that 127.0.0.1 connects while `::1` and the Mac's network address
are refused.

Also exercise all four real models, short and long recordings, downloads/removal, initial microphone
grant and denial, hold/toggle shortcuts, Globe tap and hold, Return/Escape, output destinations, live insertion on and off, surrounding text with
capitalization adaptation on and off,
model switching and idle release/reload. Check both processes in Activity Monitor, and validate
Debug and Release helper names, signatures and architecture slices. Model conversions and their
source licences must be reviewed before distribution; swapping one requires real-audio validation.

For reproducible real-model measurements, build Debug, install the models through Settings, then run:

```sh
./Scripts/benchmark-dictation.sh /path/to/sample.wav
```

The optional tool converts the supplied audio to mono 16 kHz and launches the built helper directly,
without using the microphone, clipboard or settings. It reports load and transcription times, sampled
helper `phys_footprint` in decimal MB and the recognized text, first with a fresh helper and then with
its model already loaded. macOS's file and Core ML caches remain untouched; a fresh helper is not a
cold disk-cache measurement. The 50 ms memory samples are not a guaranteed absolute peak.
Use the same audio, build configuration and otherwise idle machine for comparisons.

Optional arguments select a helper `.app`, model directory and one model's raw identifier instead of
all four. This tool is outside the deterministic suite and app targets; it neither downloads models
nor adds bundled resources.

## Cleanup and history

Cleanup and history are Notchcast's, in `Tinycast/Features/DictationExtras/`. Dictation calls in through two hooks on `DictationCoordinator`, `cleanUp` before formatting and `didDictate` after a finished session, which `DictationExtrasCoordinator` sets in `start(core:)`.

Notchcast never builds the capsule: `DictationIslandCoordinator` stands in for it and shows the session on the island on the display being typed on, which also holds Return and Escape ([island-shell.md](../../notchcast/docs/island-shell.md#dictation)).

- Cleanup is off by default; only its switch in Settings turns it on. `DictationCleanupPolicy.sends` is the one gate: with the switch off, nothing is sent. With it on, a shortcut finish (toggle, released hold or the length limit) cleans up: Return pastes the raw transcript, and live insertion and AI Chat's composer mic never clean up, because their text is already in place or the composer is its own editor.
- The transcript goes through the AI provider layer ([ai.md](ai.md)) with `permissiveContentTransformations` guardrails, never through a second provider path. The cleanup model is its own stored `AIModelSelection` (`dictationCleanupModel`, local, like Quick Actions' model); Automatic picks the installed Claude CLI, else Codex, each one's lightest model, so the user's subscription cleans up without an API key. The installed CLIs are probed while cleanup is on, even with AI and Quick Actions off.
- Only the text is sent, never the audio, and only to the chosen model. Automatic uses the Claude or Codex command signed in on this Mac. Notchcast keeps the text only in Dictation History.
- `DictationCleanupRunner` races the model against a 10-second deadline. A timeout, an error, an empty answer or a missing model falls back to the raw transcript. With the default prompt, an answer longer than 1.5 times the transcript length plus 20 characters also falls back. The island reports that cleanup failed and names a missing cleanup model when it pastes or copies raw text for that reason. When the launcher or a question covers the island, or when no island dictation session can take the report, a HUD reports the failure, with dedicated messages for a timeout or a missing model. While an enabled Claude or Codex command is still being checked, Automatic falls back silently if it has no model yet. Escape during cleanup cancels the session and pastes nothing.
- The prompt is editable in Settings; the default (`DictationCleanupPrompt.standard`) fixes punctuation, numbers, filler words and spoken corrections, keeps the speaker's language and never adds content. A blank or unchanged prompt stores nothing, so the default can improve later.
- History keeps the last 50 dictations, newest first, each with its raw transcript, the cleaned text when it differs, the time and the target app. It lives only in `dictation-history.json` in this build's bundle-ID Application Support folder: no backup, `settings.json` or sync carries it. The Keep dictation history switch is local and on by default, with no `settings.json` key, because off deletes the file; turning it off in Settings asks first.
- The Dictation History command opens a palette screen: Return pastes the text again into the app behind the palette, Command-Return copies it, Command-K offers the raw transcript, and deleting asks first only for the whole history.
- Cleanup's switch and prompt have no `settings.json` key, do not sync and are excluded from backups: the switch grants sending transcripts to a model, and the prompt decides what gets pasted.

`nc-DictationExtras-cleanup-test` checks the prompt fallback, the send gate, the absent `settings.json` keys, the runner outcomes, including missing models, probing, overlong answers and cancellation with fake models and no clock, and the Automatic model order. `nc-DictationExtras-history-test` checks recording, the cap, search and removal, and that the store persists to and deletes its own file in a temporary folder. A live cleanup with a real Claude or Codex CLI is checked by hand on a Mac.

For a mic-free Debug check in a tester guest, start `python3 notchcast/dictation-cleanup-stub.py` in the guest and export the printed port as `DICTATION_CLEANUP_STUB_PORT`. Run the Debug binary with `--island-verify`, `ISLAND_SCENE=dictation-cleanup`, the guest display ID in `ISLAND_TEST_DISPLAY` and an existing output directory in `ISLAND_OUTPUT`. Run it with `ISLAND_LOOK=black` and again with `ISLAND_LOOK=frosted`, using separate output directories. The scene starts the real cleanup hook, skips recording and pasting, and checks stored history for a successful answer, an HTTP failure, a timeout, an empty answer and an overlong answer. The stub prints exactly five validated request bodies per scene run. Missing model, HTTP failure and timeout each capture a HUD.
