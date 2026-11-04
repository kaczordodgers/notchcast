# Archives

`Archives` starts `ArchiveModule` through `NotchcastCore.archiveModuleEntries`. It defaults on and
does not require the island. File opens use the existing `AppDelegate` → `AppCore.handleOpenURL`
path after launch-time URLs have been deferred. Only local archive URLs are accepted; plain `.gz`
files are excluded. Turning Archives off rejects new opens and retries immediately and cancels queued
and active jobs. Quitting waits for the archive child to stop and staging cleanup to complete.

Settings → Notchcast has one Archives section containing its three switches, the hatchzip location
or an installation hint, and the queue. Each job exposes its name, progress, state, failure and
in-place fallback note, with Cancel, Try Again and Show in Finder actions as applicable.

`Extract in place` defaults off. It affects newly opened jobs; retries preserve the original mode
and recovery information. Its parent switch is Archives. The archive shrinks during extraction;
the engine retains resumable journals when cancelling in-place jobs and falls back to keep mode
when hatchzip refuses in-place extraction. Listings with symlinks or no entries also use keep mode,
as do volumes without exclusive rename support. If final validation fails after in-place consumption,
the staging folder is published visibly with a recovered name.

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
