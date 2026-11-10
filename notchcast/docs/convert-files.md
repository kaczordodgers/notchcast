# Convert Files engine

`ConvertFilesPlan.make` accepts local file URLs, a target extension or PDF operation,
an optional page range and an injected set of occupied outputs. It performs no IO.

`ConvertFilesRunner` implements `DownloadRunner` with kind `convert-files`.
Job options are `ConvertFilesRunner.Options`: the absolute `sources` paths, `target` and `pages`. A job without them, as an older build queued it, fails with a message to add the files again rather than converting a guessed source.
Its injected `process` closure receives an executable, argv and the shared download context.
The only result notification is `post`, called on the main actor for each success or failure.
Successful batch outputs remain available when another item fails. Cancellation propagates.

Attach `ConvertFilesModule` to the existing `DownloadQueue` with `attach(to:post:)`.
The module owns no queue or process manager. Its feature switch gates submissions.
Commands remain unregistered for the command integration lane.

Native image, PDF and data work runs in process off the main actor through `@concurrent`.
Cancellation is checked between files, PDF pages and data records, and before publishing.
No native conversion needs a toolchain or child process. External conversions continue to use
the injected process runner and resolve tools through `DownloadToolLookup`.
Outputs stage in unique sibling scratch folders and publish through `JobOutput.publish`, an exclusive rename.
Existing outputs are never replaced, including when another writer creates the chosen name.

Implemented operations include PDF merge, split, page ranges and selectable text extraction; ImageIO encoding,
cwebp and sips images; textutil and sandboxed pandoc documents; ffmpeg media and subtitles;
bsdtar packing and extraction; JSON, CSV, and flat YAML/TOML tables.

Remaining coverage: nested YAML/TOML (rejected explicitly), PDF page rendering, webarchive output,
all embedded subtitle tracks, legacy image decoder fallback and richer media encoding options.
Fonts require Python/fontTools and are intentionally excluded.

The source reference is the media converter port; its MIT notice is in `LICENSE.upstream`.
