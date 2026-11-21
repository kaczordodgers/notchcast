# Archives

The Archives add-on (`Tinycast/Features/Notchcast/Archives/`), under the **Archives** switch in Settings › Notchcast › Downloads, extracts archives in place of Archive Utility and compresses a Finder selection. Progress, results and failures are island notices; a question goes through the core's `confirm` dialog, a password through its `askSecret` dialog.

## Invariants

- **Nothing is bundled.** Every tool is the user's own install, found with `ExecutableLocator.locate`; a missing one is a failure notice naming it and its install line.
- **Never over an existing file.** Output takes the first free name (`ArchivePlacement.freeName`: `Trip`, `Trip 2`, `Trip 3`…). Extraction moves staged items into place by rename; compression publishes with `renamex_np(RENAME_EXCL)` and moves on to the next number if a name was taken meanwhile; where the disk lacks it (exFAT, SMB: `ENOTSUP`), with `FileManager.moveItem`, which also refuses a taken name but not atomically.
- **Output lands beside the input**: extracted items beside the archive, an archive beside the selection.
- **A stop or failure leaves nothing half-done.** Extraction keeps only what HatchZip already moved out in place, and the one exception under Protected archives; compression writes in a private folder on the output's volume (`.itemReplacementDirectory`), removed on every exit, and publishes on the main actor after checking for a stop.
- **A password is never kept.** It lives in one local variable of `ArchiveExtractor.extract` for one job and reaches HatchZip only as `HATCHZIP_PASSWORD` in the environment of its `list`, `extract` and `check` runs: never an argument, the journal, a notice, a log, the Keychain or the pasteboard.
- **One extraction and one compression at a time.** Extraction is a queue journalled to `archives.json`, so a relaunch resumes it; compression is in memory only, and a second request while one runs is refused with a notice. The two run side by side.

## Extract

Opening an archive with Notchcast (or "Extract Archive…") queues it. `ArchiveRoute` picks the engine from the name: HatchZip for most formats, bsdtar, unar, or a single-stream decompressor under a size cap. A listing is checked by `ArchiveSafety` before anything is written. One top-level item lands beside the archive under its own name; several land in a folder named after the archive. "Extract in place" removes the archive as its files come out, for when keeping it does not fit; HatchZip asks for that itself when space runs out. "Make Notchcast the default app for archives" claims the archive types once, and switching the add-on off hands them back.

## Protected archives

HatchZip usually asks for a password when listing a protected ZIP, 7z or RAR. Notchcast responds to exit 5 by asking for the password ("Password for <name>") and retrying the step. An extraction that first requests a password gets the same prompt and retries; a wrong one asks again with "That password did not work.", up to three passwords in all, then fails with "The password was not accepted." Cancel stops the job with "Stopped extracting <name>", nothing written. Each job asks on its own: a second archive, or a job resumed after a relaunch, asks again. A protected ZIP may go in place as any ZIP; a protected 7z or RAR is always kept, whatever "Extract in place" says, and is never offered in place when space runs out.

- **The environment variable's limit:** while HatchZip runs, which for a big archive is the whole extraction, the password is readable by the same user's other programs (`ps eww <pid>`) and by root, though not by other users; `ps -ax -o args` shows no password. HatchZip's own hidden prompt needs a terminal, so this is the tightest way open to an app.
- **A stopped protected 7z or RAR with encrypted file names keeps its staging folder and HatchZip's side files.** The stopped entry in `archives.json` records the archive's path, size and stop time. A reopen with the same path and size resumes into that staging folder if HatchZip's `<archive>.hatchzip` file still exists. With the side file gone, Notchcast discards the old staging and starts fresh. HatchZip binds its recovery files to the original archive path. If the archive and its recovery files are moved or renamed, Notchcast asks you to restore their original names and location. A staging folder reported by HatchZip is only eligible if its stopped entry matches the opened archive's path and size. Cancel at the password question, Cancel All Extractions and switching Archives off preserve the stopped entry.
- **At launch**, Notchcast removes a stopped entry and its staging only if the archive path is missing and the entry is more than seven days old. A stopped entry without a recorded stop time stays available for recovery.
- **Progress HatchZip holds for an unknown folder** fails with "This archive is partly extracted elsewhere; finish that with hatchzip first." The reported folder, side files and any stopped entries stay untouched.
- **Not covered:** the `unar` route (old Mac formats, and ZIPs with legacy Windows names when `unar` is installed) takes a password only as a command-line argument, so a protected archive there fails with `unar`'s own sentence; bsdtar and single-file routes carry no passwords.

## Compress

"Compress to ZIP", "Compress to 7z" and "Compress to .tar.zst" read Finder's selection through the core's `NotchcastAppleEvents.finderSelection` (Automation refused becomes our own notice) and make one archive:

- one item is named after itself with its whole name (`notes.txt.zip`, `Photos.7z`); several are named after their folder (`Trip.tar.zst`), the number going before the whole extension (`Trip 2.tar.zst`); a long name is cut to fit 255 bytes, its extension and a number, never through a character;
- refused before any tool runs: nothing selected, items from more than one folder, `/`, anything that is not a file, folder or symbolic link, a folder Notchcast cannot write to;
- the island shows a progress notice while it runs; a tap on it asks before stopping; a tap on the result reveals it in Finder.

| Format | Tool | Install | Command line |
| --- | --- | --- | --- |
| ZIP | `ditto` | ships with macOS | `ditto -c -k --sequesterRsrc [--keepParent] <item> <out>`; several items, or a lone link, are cloned into a private folder and zipped from there, so they sit at the top level and links stay links |
| 7z | `7zz`, else `7z` | `brew install sevenzip` | `7zz a -t7z -mx=9 -snl -spd -bd -y -- <out> <absolute paths>` |
| .tar.zst | `bsdtar` and `zstd` | `brew install zstd` | `bsdtar --use-compress-program "<zstd>" -cf <out> -C <folder> ./<name>…`; stock bsdtar cannot write zstd itself, so the located `zstd` is passed, quoted, with `\` and `"` escaped |

`Tests/nc-Archives-model-test.swift` covers routing, naming, refusals and every argument list. `nc-Archives-module-test.swift` drives extraction with fake tools. `nc-Archives-password-test.swift` drives protected archives with a fake HatchZip and, when installed, the real one on tiny ZipCrypto, AES ZIP and AES 7z fixtures. `nc-Archives-recovery-test.swift` covers stopped extraction, reopening after a modification, rejecting moved archives and unknown or foreign staging, and expiry with a fake HatchZip. It also covers reopening without the side file using the fake and, when installed, real HatchZip. `nc-Archives-compress-test.swift` drives compression with fake tools.
