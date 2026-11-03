# Distill engine

`DistillQueue` stores cleaned, deduplicated links in an explicitly supplied file. Import callers supply
the old Orion or Damian Tools queue URL; the source is read only and an import marker is committed
with the added links. Removing imported links does not import them again on the next launch.

`DistillRunner.run(source:destination:times:execution:progress:)` fetches media metadata and native
audio with yt-dlp, transcribes it, then publishes `Channel - Title.txt`. Filenames replace filesystem
reserved characters and limit each component to 100 UTF-8 bytes. Existing files receive a numbered
suffix. Publication uses a same-directory hard link so the complete file appears without replacing
another file. An empty transcript is an error. The caller supplies the destination; later settings
can supply `~/Downloads/Distill/Raw` as their default. No output is ingested or deleted.

Unknown web hosts go to the injected webpage saver. Browser cookies are off. All child commands are
injected through `DistillExecution.spawn`; its implementation must await completion, return stdout,
throw on a nonzero exit and cancel the process group with its owning task.

## File transcription API for Convert

Create a transcriber from the existing app-owned Dictation model store on the main actor:

```swift
let transcriber = modelStore.distillTranscriber(model: selectedModel)
let segments = try await transcriber.transcribe(
    file: mediaFile, workDirectory: scratchRoot, execution: execution)
let text = DistillTranscript.text(segments, times: false)
```

`file` accepts audio or video supported by ffmpeg. The source remains unchanged. ffmpeg extracts the
first audio stream to 16 kHz mono little-endian Float32 in an operation-private scratch directory.
Only one four-minute window is loaded at a time. Consecutive windows overlap by two seconds; matching
suffix/prefix words are removed ignoring case and punctuation, with at least two matching words.
Uncertain boundaries retain the words rather than dropping unmatched speech. All temporary audio is
removed after success, failure or cancellation.

The upstream helper accepts at most five minutes per request. Distill sends sequential four-minute
requests through `DictationModelStore.transcribe` with `language: nil` (automatic detection). It does
not use the microphone or clipboard, and does not download a model during an ordinary run. The
existing store owns helper reuse, cancellation, model removal and idle release. If Dictation is busy,
its existing busy error propagates. No upstream Dictation file is changed.

The helper returns plain text without word alignments. `Segment.start` is the approximate beginning
of the source chunk, including its overlap, never a fabricated word timestamp. Optional `[hh:mm:ss]`
prefixes therefore have chunk-level precision. Progress reports completed and total chunks.

`transcribePCM(file:progress:)` accepts an already normalized Float32 file and is also used by the
standalone harness. `DISTILL_TEST_ROOT` selects the harness scratch directory; otherwise it uses an
isolated temporary directory. The optional `--live` mode accepts explicit scratch, helper and build
model cache paths plus a public video URL. It runs the complete engine with real child commands,
uses an already installed model or downloads Redux with the upstream downloader, and saves the
transcript into the scratch directory's `Raw` folder.
`DISTILL_EXISTING_MODEL` can point at a compatible installed Parakeet v3 directory; the live fixture
creates a symlink in its supplied model root and never modifies the existing model directory.

Queue registration and the concrete process adapter wait for the Downloads queue pack to land.
