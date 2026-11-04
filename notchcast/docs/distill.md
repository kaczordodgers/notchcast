# Distill engine

`DistillQueue` stores cleaned, deduplicated links in an explicitly supplied file. Import callers supply
the old Orion or Damian Tools queue URL; the source is read only and an import marker is committed
with the added links. Removing imported links does not import them again on the next launch.

`DistillRunner`, registered as kind `distill`, fetches media metadata and native
audio with yt-dlp, transcribes it, then publishes `Channel - Title.txt`. Filenames replace filesystem
reserved characters and limit each component to 100 UTF-8 bytes. Existing files receive a numbered
suffix. Publication uses a same-directory hard link so the complete file appears without replacing
another file. An empty transcript is an error. The caller supplies the destination; the Notchcast module defaults to `~/Downloads/Distill/Raw`. No output is ingested or deleted by Distill.

Unknown web hosts and Spotify go to the injected webpage saver; the default reports it is not connected.
Browser cookies are off. All child commands use `DownloadRunContext.spawn`, which owns process-group
cancellation and failure details. Supply a queue with `maxConcurrent: 1` for serial Distill batches.
The context supplies the destination; the `timestamps` job option enables chunk times when `true`.

## File transcription API for Convert

Create a transcriber from the existing app-owned Dictation model store on the main actor:

```swift
let transcriber = modelStore.distillTranscriber(model: selectedModel)
let text = try await transcriber.text(
    file: mediaFile, workDirectory: scratchRoot, context: context)
```

`file` accepts audio or video supported by ffmpeg. The source remains unchanged. ffmpeg extracts the
first audio stream to 16 kHz mono little-endian Float32 in an operation-private scratch directory.
Only one four-minute window is loaded at a time. Upstream's quiet-point cutter chooses a boundary
in its final three seconds. Consecutive chunks are contiguous without duplicated audio or text deduplication.
The final chunk keeps all remaining samples. All temporary audio is
removed after success, failure or cancellation.

The upstream helper accepts at most five minutes per request. Distill sends sequential four-minute
requests through `DictationModelStore.transcribe` with `language: nil` (automatic detection). It does
not use the microphone or clipboard, and does not download a model during an ordinary run. The
existing store owns helper reuse, cancellation, model removal and idle release. If Dictation is busy,
Distill retries every 100 milliseconds without a timeout; cancellation interrupts the wait.
Other errors propagate. No upstream Dictation file is changed.

The helper returns plain text without word alignments. `Segment.start` is the approximate beginning
of the source chunk, never a fabricated word timestamp. Optional `[hh:mm:ss]`
prefixes therefore have chunk-level precision. Progress reports completed chunks and an estimated total.

`transcribePCM(file:progress:)` accepts an already normalized Float32 file and is also used by the
standalone harness. `DISTILL_TEST_ROOT` selects the harness scratch directory; otherwise it uses an
isolated temporary directory. The harness exercises fake media tools through the real queue context.
Queue registration is owned by the Notchcast modules described in [downloads.md](downloads.md). Typed launcher entries are compiled and tested; launcher registration awaits the command hook.
