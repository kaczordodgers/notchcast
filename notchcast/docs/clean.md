# Clean settings

Clean's seven switches are off by default and independent of the island. `CleanModule` owns the coordinator and live transports; one module entry starts switch observation while any Clean switch is on. Turning a switch off cancels that feature's work and discards its review. No scan, cleanup, or optimization starts automatically.

The Settings rows use native controls inside the Notchcast pane's Clean section. Scan results are initially unselected. Disk analyzer accepts one picked folder and Purge accepts picked project roots. The coordinator captures the reviewed selection, asks through `DialogController` with Cancel as the default, and checks cancellation, switch state and operation identity after suspension. Trash operations call the engines, which revalidate their own snapshots and policies before calling the recorded trash transport. Disk selections omit descendants of another selected folder from both confirmation totals and execution.

AI data lists only the engine's Claude, Codex, OpenCode and worktree sources. Codex and OpenCode are report-only. Claude chats require verified idle state and a verified recovery copy; worktrees require the engine's Git eligibility checks and verified idle state. Unknown Git or process state never grants deletion.

History records trash destinations returned by FileManager and uses the history engine's exclusive restore. Restore roots are each record's exact original and trash parent directories. Existing destinations are never overwritten, and the engine rejects unsafe paths and symbolic links. Actions on records without a trash destination remain unavailable.

System root uses helper contract 4 with `clean-system-list` and `clean-system-trash`. Each Scan and each trash batch checks the helper version. Listing and trashing share the protected-parent check; writable parents are excluded from results and refused again before a move. Both sides enforce `CleanSystemPolicy` and reject NUL paths; JSON decoding rejects invalid UTF-8. The helper rechecks file identity and refuses symlink ancestors and traversal before moving files into the invoking user's existing Trash. A batch continues after individual failures and reports their count. Files stay recoverable there; this mode does not report freed bytes.

Each Optimize verb has its own explicit button and confirmation naming what it resets, clears, or rebuilds. The engine provides no size preview, so these questions state that the size is unknown and do not invent an item count. Cancel is the default, as approved for these actions.

`Tests/nc-Clean-wiring-test.swift` injects fake scans and trash transport under a fresh temporary directory. It covers default-off behavior, listener teardown, declined confirmation, reviewed-only execution, stale scan results, and missing helper verbs. Engine harnesses separately cover revalidation and path policy. No harness launches the app or runs a scanner against personal data.
