# Archives

`Archives` starts `ArchiveModule` through `NotchcastCore.archiveModuleEntries`. It defaults on and does not require the island. File opens use the existing `AppDelegate` → `AppCore.handleOpenURL` path after launch-time URLs have been deferred. Only local archive URLs are accepted, including plain compressed files. Turning Archives off rejects new opens and retries immediately and cancels queued and active jobs. Quitting waits for the archive child to stop and staging cleanup to complete.

`ArchiveEngineRoute` keeps `.zip`, `.7z`, `.rar`, `.tar`, `.tgz`, `.tar.gz`, `.001` and `.rNN` on hatchzip. A ZIP central-directory name with invalid UTF-8 bytes and without general-purpose UTF-8 bit 11 routes to XADMaster instead. Other ZIPs keep their existing hatchzip path, including in-place extraction and journal resumes. XADMaster’s detector can misread short CP852 names as Windows-1252. A conservative hint selects IBM852 or Windows-1250 only when at least three distinct legacy bytes fit exclusively that encoding’s Polish letter set; all other names retain XAD detection. The same encoding is used for listing and extraction.

System `/usr/bin/bsdtar` handles `.tar.xz`/`.txz`, `.tar.bz2`/`.tbz2`, `.iso`, `.cab`, `.pkg`/`.xar` and `.cpio`. macOS libarchive 3.7.4 lacks zstd, so Homebrew `zstd -d` handles `.zst` and decompresses `.tar.zst`/`.tzst` into staging before bsdtar lists and extracts the tar. Plain `.gz`, `.xz` and `.bz2` use system `/usr/bin/gzip -d -c` through the bounded, cancellable process runner. Plain compressed files produce one file named by removing the final suffix, ignoring any embedded filename.

Homebrew XADMaster (`lsar`/`unar`, installed with `brew install unar`) handles `.sit`, `.sitx`, `.lzh`/`.lha`, `.arj`, `.z`, `.arc`, `.zoo` and legacy-encoding ZIPs. This deliberately bounded list follows XADMaster’s registered StuffIt, LZH, ARJ, Compress, ARC and Zoo parsers. Nothing is bundled; missing Homebrew tools fail only affected jobs and report `brew install unar` or `brew install zstd`.

Fallback engines always keep the archive, even when Extract in place is enabled. They reuse job rows, progress, cancellation, staging, recovery records and publication. Bounded `bsdtar -tv` and `lsar -j` listings pass through `ArchiveRules.validate` before extraction; unknown listing shapes, hardlinks and device nodes are rejected. XAD extraction reuses the detected listing encoding, disables recursive unpacking and preserves native resource forks. Fork-only paths and duplicate forks are validated, and fork sizes count toward the expansion limit. Raw streams are counted before writing and enforce the same expansion limit while streaming. Intermediate zstd tar files remain inside staging, are checked against member-name collisions and are removed before publication. Every extraction reserves 2 GB free.

Compression runs under the existing Archives switch, without a panel or window. Finder Services and the three launcher commands share the archive queue: Compress with Notchcast uses system ditto ZIP, Compress Small uses Homebrew sevenzip, and Compress Fast uses system bsdtar with Homebrew zstd. Launcher commands read the current Finder selection. The command catalog has no argument field, so password encryption is omitted. Missing tools report `brew install sevenzip` or `brew install zstd`. Several items produce one archive named after their shared parent, or Archive when the parents differ; output goes beside the first source. A single item keeps its name. Collisions use numbered names, and exclusive rename prevents overwrites. Hidden staging is removed on failure or cancellation. Compression never uses the extraction journal or in-place mode. ZIP selections with several items are copied into hidden staging before ditto runs. Duplicate leaf names are staged for every format with numbered names preserving extensions; 7z and tar otherwise read sources directly. Publication retries exclusive rename collisions. Finder Services titles use ServicesMenu.xcstrings. Job states and results use the existing rows and notch messages.

`nc-Archives-compress-test` checks exact commands, naming, failure cleanup and real ZIP, 7z and tar.zst round trips with Polish filenames, nested directories and an empty file. It locates Homebrew sevenzip and zstd, explicitly skipping unavailable real-tool checks. Duplicate-leaf round trips and publication races are covered.

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
`ArchiveDefaultApplicationService` for the claimable archive UTIs. Defaults preserve the previous claims, including RAR and split `.001`, and add supported types declared by Archive Utility; `.iso` and `.pkg` remain excluded. Other supported formats remain available through Open With and launcher opens. Disabling it, including by disabling
Archives, gives handlers still owned by this app back to Archive Utility. Handler writes are
serialized, including when switches change during a write or a write only partly succeeds.
Quitting preserves an opted-in handler so the next file open can launch Notchcast. A successful claim
is persisted so launch does not override subsequent handler choices. Restore only targets types
declared by Archive Utility, so RAR and split `.001` cannot be handed back, as before; per-type errors are collected and reported after all types are tried.

The document declarations use the Alternate rank, so registration alone does not claim defaults. The gzip, xz, bzip2 and zstd UTIs offer both plain streams and their `.tar` variants; compound aliases `.tgz`, `.txz`, `.tbz2` and `.tzst` and split `.001` have separate tags; archive imports include `app.notchcast.*` and `com.rarlab.rar-archive`, which the system does not declare. Multi-component filename extension tags are not used. Preferences stay in the existing bundle-scoped Notchcast suite.

`nc-Archives-fallback-test`, `nc-Archives-engine-test`, `nc-Archives-modules-test` and `nc-Archives-routing-test` cover the engine,
module ownership, switch defaults and gating, mode selection, shutdown, fake handler effects, document
declarations, routing and settings search. Handler tests always inject a fake service. Fixture files
are created under the runner's `TMPDIR` and never use existing user archives.

The fallback harness uses `notchcast/test-archives-fallback.py` to generate tar.xz, tar.bz2, plain gz/xz/bz2/zst, tar.zst, an ISO with `hdiutil makehybrid`, and a ZIP with raw CP852 Polish names and bit 11 unset. It extracts through the shipping runner, compares every filename and byte against the sources, and verifies unsafe tar/ZIP members are rejected without leaving staging or escaped files. Installed `unar`, `lsar` and `zstd` are required for that real-tool section; missing tools are reported as Not verified.
