# Convert Files engine

`ConvertFilesPlan.make` accepts local file URLs, a target extension or PDF operation and an optional page range. It performs no IO and names no file: each item carries a stem and suffix, its arguments hold `ConvertFilesPlan.outputPlaceholder`, and `JobOutput.publish` picks the free name once the conversion is done.

`ConvertFilesRunner` implements `DownloadRunner` with kind `convert-files`.
Job options are `ConvertFilesRunner.Options`: the absolute `sources` paths, `target` and `pages`. A job without them, as an older build queued it, fails with a message to add the files again rather than converting a guessed source.
Its injected `process` closure receives an executable, argv and the shared download context.
The only result notification is `post`, called on the main actor for each success or failure.
Successful batch outputs remain available when another item fails. Cancellation propagates.

Attach `ConvertFilesModule` to the existing `DownloadQueue` with `attach(to:post:)`.
The module owns no queue or process manager. Its feature switch gates submissions.
Commands remain unregistered for the command integration lane.

Native image, PDF and data work runs in process off the main actor through `@concurrent`. Cancellation is checked between files, PDF pages and data records, and before publishing. No native conversion needs a toolchain or child process. External conversions continue to use the injected process runner. The plan lists typed tool requirements, including ffprobe only for audio and video. The runner resolves the whole batch through `DownloadToolLookup` before converting any file and reports missing tools as `DownloadToolMissing`. Outputs stage in unique sibling scratch folders and publish through `JobOutput.publish`, an exclusive rename. Existing outputs are never replaced, including when another writer creates the chosen name.

Implemented operations include PDF merge, split, page ranges and selectable text extraction; ImageIO encoding,
cwebp and sips images; textutil and sandboxed pandoc documents; ffmpeg media and subtitles;
bsdtar tar.gz packing; JSON, CSV, and flat YAML/TOML tables.

zip and 7z packing and every extraction go to Archives: the plan marks them `archives`, and `ConvertFilesRunner.archive` (hub glue in `Notchcast/Tools`, so neither feature folder names the other) calls `ArchiveCompressor` and `ArchiveExtractionRunner`. Archives stages, checks the listing, carries the quarantine and names the output by its own rules, so these items skip the scratch folder and `JobOutput.publish` here. They need what Archives needs: hatchzip to extract `.zip`, `.7z`, `.rar`, `.tar`, `.tgz`, `.tar.gz` and split `.001` archives, `unar` for a zip with Windows-encoded names, `7zz` for 7z packing. Archives runs one extraction at a time through `ArchiveExtractionGate`, so a Convert Files extraction waits for a running Archives job and the other way round. tar.gz packing stays on bsdtar because Archives has no such format.

Remaining coverage: nested YAML/TOML (rejected explicitly), PDF page rendering, webarchive output,
all embedded subtitle tracks, legacy image decoder fallback and richer media encoding options.
Fonts require Python/fontTools and are intentionally excluded.

The source reference is the media converter port; its MIT notice is in `LICENSE.upstream`.
