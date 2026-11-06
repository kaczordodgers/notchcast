# Archives

Compression runs under the existing Archives switch, without a panel or window. Finder Services and the three launcher commands share the archive queue: Compress with Notchcast uses system ditto ZIP, Compress Small uses Homebrew sevenzip, and Compress Fast uses system bsdtar with Homebrew zstd. Launcher commands read the current Finder selection. The command catalog has no argument field, so password encryption is omitted. Missing tools report `brew install sevenzip` or `brew install zstd`. Several items produce one archive named after their shared parent, or Archive when the parents differ; output goes beside the first source. A single item keeps its name. Collisions use numbered names, and exclusive rename prevents overwrites. Hidden staging is removed on failure or cancellation. Compression never uses the extraction journal or in-place mode. ZIP selections with several items are copied into hidden staging before ditto runs. Duplicate leaf names are staged for every format with numbered names preserving extensions; 7z and tar otherwise read sources directly. Publication retries exclusive rename collisions. Finder Services titles use ServicesMenu.xcstrings. Job states and results use the existing rows and notch messages.

`nc-Archives-compress-test` checks exact commands, naming, failure cleanup and real ZIP, 7z and tar.zst round trips with Polish filenames, nested directories and an empty file. It locates Homebrew sevenzip and zstd, explicitly skipping unavailable real-tool checks. Duplicate-leaf round trips and publication races are covered.

`Archives` starts `ArchiveModule` through `NotchcastCore.archiveModuleEntries`. It defaults on and
does not require the island. File opens use the existing `AppDelegate` → `AppCore.handleOpenURL`
path after launch-time URLs have been deferred. Only local archive URLs are accepted; plain `.gz`
files are excluded. Turning Archives off rejects new opens and retries immediately and cancels queued
and active jobs. Quitting waits for the archive child to stop and staging cleanup to complete.

Our features live in a Notchcast category in the Settings sidebar, one tab per module. Every switch has a working function, and its commands sit under it. Turning a switch off removes its commands. Each job exposes its name, progress, state, failure and
in-place fallback note, with Cancel, Try Again and Show in Finder actions as applicable.

`Extract in place` defaults off. It affects newly opened jobs; retries preserve the original mode
and recovery information. Its parent switch is Archives. The archive shrinks during extraction;
the engine retains resumable journals when cancelling in-place jobs and falls back to keep mode
when hatchzip refuses in-place extraction. Listings with symlinks or no entries also use keep mode,
as do volumes without exclusive rename support. If final validation fails after in-place consumption,
the staging folder is published visibly with a recovered name.

Extraction writes an atomic JSON sidecar beside staging at running, finished-extract and publishing
transitions. Launch checks remembered archive directories; opening the same archive also checks its
sidecar. Finished output is published visibly, with a recovered name on collision. Interrupted keep
jobs retain their source and discard staging; interrupted in-place journals remain available through
Try Again. Unclaimed nonempty staging is recovered visibly, while empty staging is removed.
Engine boundaries resolve parent directories before comparing archive, staging and recovery URLs.
The final component retains its symlink checks; hatchzip resumes use its saved destination spelling.
Orderly shutdown cancels the worker and signals the child process group. There is no parent-death
watchdog: a hard app kill relies on recovery at the next launch.

`Open archives with Notchcast` defaults off and also depends on Archives. Enabling it calls
`ArchiveDefaultApplicationService` for the declared archive UTIs. Disabling it, including by disabling
Archives, gives handlers still owned by this app back to Archive Utility. Handler writes are
serialized, including when switches change during a write or a write only partly succeeds.
Quitting preserves an opted-in handler so the next file open can launch Notchcast. A successful claim
is persisted so launch does not override subsequent handler choices. Restore only targets types
declared by Archive Utility, and per-type errors are collected and reported after all types are tried.

The document declarations use the Alternate rank, so registration alone does not claim defaults.
The gzip UTI offers `.tar.gz` files; the router still rejects plain `.gz` files. The `.tgz` and
split `.001` tags are imported separately. Multi-component filename extension tags are not used.
Preferences stay in the existing bundle-scoped Notchcast suite.

`nc-Archives-engine-test`, `nc-Archives-modules-test` and `nc-Archives-routing-test` cover the engine,
module ownership, switch defaults and gating, mode selection, shutdown, fake handler effects, document
declarations, routing and settings search. Handler tests always inject a fake service. Fixture files
are created under the runner's `TMPDIR` and never use existing user archives.
