# Downloads and Distill wiring

## Invariants

- Downloads and Distill have separate queues and lifetimes, controlled by their own visible switches independently of Island.
- Queue shutdown finishes before a replacement queue opens the same persistence file. A cancelled startup never publishes its queue.
- aria2c and timestamp options are read from the observable preferences when a job begins, including jobs that waited in the queue. Changing an option does not restart the module or a running job.
- Disabling Convert unregisters its runner and cancels its unfinished jobs. Disabling either module stops and releases its queue.
- Clipboard actions accept only explicit HTTP or HTTPS links, deduplicate them and reject embedded credentials. Distill additionally applies the engine's link cleaner.
- Links leave the Distill link list only after their download jobs have been persisted. A persisted link identifier prevents a repeated transfer after interruption.
- Transcription reuses a separate Dictation model store and selected model with automatic language detection. Running a command never installs tools or downloads a speech model.

## Ownership and storage

`NotchcastCore` owns `DownloadsModule` and `DistillModule` through its module controller. Their wiring lives in `Tinycast/Features/Notchcast/Downloads/`; the engines remain in `Features/Downloads/` and `Features/Distill/`.

The current bundle's Application Support directory holds `Notchcast/downloads.json`, `Notchcast/distill.json` and `Notchcast/distill-links.json`. Downloads writes to `~/Downloads`; Distill writes to `~/Downloads/Distill/Raw` and runs one job at a time. Temporary transcription audio lives in the current bundle's `Notchcast/Transcription` cache directory.

The Downloads module registers video, audio, transcript and webpage runners. Captionless transcripts transcribe only supported media audio and save `Title [id].txt`, adding ` (2)` when taken; non-media links fail without saving a webpage. Distill's webpage seam calls `WebpageSaver`; Convert uses `HTMLMarkdown` for HTML and MHTML and `DistillTranscriber` for audio and video. Converted media retains its original; the conversion engine verifies output before any permitted move to Trash.

## Commands and activity

`NotchcastDownloadCommands` supplies nine typed entries with localized titles, English search keywords, SF Symbols, feature requirements and actions. Entries are filtered by the live switches and actions check the switches again after queue startup. Empty clipboard input produces a status callback, which defaults to the system beep. Clipboard, status and folder-opening effects are injectable. Entries remain unregistered until the launcher command hook lands.

Both modules expose `DownloadsActivity`, computed from observable queue jobs: running count, oldest running title, fraction and stage. A future island consumer can also build one activity value from both queues' jobs. No island presentation is registered yet.

## Verification

`Tests/notchcast-downloads-wiring-test.swift` declares its compiler sources in metadata for automatic harness discovery. Run `./Scripts/run-tests.sh notchcast-downloads-wiring-test`; it creates an isolated temporary directory. It exercises switches, queue replacement and shutdown, command gating, clipboard parsing, delayed jobs reading live options, progress observation, captionless fallback, Distill web links, conversion and conversion cancellation with fake tools and injected file effects. It never opens Finder, the system clipboard, real output folders or the network.

Settings uses the shared Options loop, with all five switches independent of Island. Child switches remain editable when their parent is off; their options take effect only while the parent module runs. One Downloads section lists the fixed output folders using standard Settings components.

## Speech worker ownership

Downloads and Distill share one services instance and DictationModelStore created by NotchcastCore, using the same installed model files and currently selected model as Dictation. They never download or install a model; a missing model produces the upstream not-installed failure. User dictation runs in its separate store and worker, so background chunks cannot make it busy.
The worker stays loaded across chunks and consecutive queued transcription jobs, then releases when no transcription job is running or queued, or after module shutdown. Each chunk waits while the user's Dictation model store is transcribing.
