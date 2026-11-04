# Media tools engine

On-demand native compression, GIF creation and text extraction. No files are overwritten:
each operation stages beside its input and publishes with an exclusive hard link. Cancelling
or disabling the module cancels its owned task and discards staged output. No polling or
media objects remain while idle.

`MediaToolsRunner.run(_:tool:)` returns the published URL. `MediaToolsModule.run(_:tool:post:)`
reports the resulting path or localized failure through its main-actor closure. Video uses
H.264 quality 0.68, longest side at most 1280 pixels and at most 30 fps, retaining the first
audio track as AAC. Target mode retries lower bitrates and publishes only measured output
within the requested bytes; impossible targets fail. Images are JPEG quality 0.72 with a
1600-pixel default limit and source metadata removed. GIFs use 720 pixels and 12 fps, capped
at 120 seconds to bound work. PDF text is read directly, with Vision OCR for scanned pages;
images use Vision OCR. Cancellation is checked between OCR pages and image operations.

Behavior references: [media service](https://github.com/vorssaint/vorssaint-utils/blob/main/Sources/Vorssaint/Services/Media/MediaService.swift),
Copyright (C) 2026 Vorssaint, GPL-3.0-or-later, and the local media conversion reference.
This engine uses native APIs directly and carries no external executable or runtime dependency.

Excluded: general format conversion, watermarking, rename patterns, profiles, shelf and drop UI.

GIF export accepts at most 30 seconds, samples at 12 fps and caps frames at 480 pixels.
