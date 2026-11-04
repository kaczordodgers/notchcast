# Katana engines

The Katana switch starts and stops the channel client and audio service. Both default to disconnected: this port has no CoreMIDI, CoreAudio, Bluetooth, USB or subprocess backend, discovers no devices and sends nothing to hardware. Tests inject fake transports. The visible switch uses the System group of the existing Notchcast settings section.

## Invariants

- `KatanaClient` serializes operations and invalidates results on stop. `KatanaTransport.send` sends DT1 without waiting for an echo (including editor mode, selection, regions and PREVIEW_MUTE). `exchange` waits for read replies and PATCH_WRITE/EXPORT echoes only. A future backend must collect fragmented packets, drain dumps, bound waits, honor cancellation and acquire the shared amp lock.
- A channel change sends one select request and reads the active channel up to eight times. Tone loading atomically backs up every stored-slot region and knob layer before editing, then writes and reads back each region in 128-byte chunks before PATCH_WRITE, PREVIEW_MUTE and EXPORT. Backup failure prevents overwrite. PANEL persists without PATCH_WRITE. Cleanup always attempts unmute on the original connection, including after stop or cancellation. The two unsupported derived SOLO_DELAY bytes are excluded from readback comparison.
- `.kat`, `.kat2`, `.kat3` and `.tsl` import is offline. MkI/MkII conversion uses the existing conversion tables from Damian's own implementation, derived from the `katana-tools` maps. `converted` records that the tone may have lost unsupported effects. GA-FC assignments are omitted. Gen 3 knob-page offsets use unpacked 7-bit addresses. Missing optional regions receive initialized values, so a partial tone cannot inherit effects from the previous channel.
- Raw-backed `katana-tools` JSON presets apply their `set` overlays before loading. Imports validate every file before replacing the library atomically; a rejected file preserves the existing library. The library path is injected and the app uses its bundle-specific Application Support directory. No source preset folder is hardcoded or modified.
- Tuning uses the source tool's McLeod pitch method over injected samples, evaluated off the main actor. Audio transport accepts USB only, with dry input 3 and wet inputs 1/2. Recording requests stereo AAC at 256 kb/s and mono Apple Lossless; the future audio backend owns file reservation, encoding, finalization and cancellation cleanup. Stop tears down audio, and stale results cannot restore state.

## Commands

The callable surfaces are `KatanaClient.refresh`, `selectChannel`, `loadTone`, `refreshAudioSettings`, `setAudioSettings`; `KatanaToneStore.refresh` and `importFiles`; and `KatanaAudioService.tune`, `stopTuning`, `startRecording`, `finishRecording`. They propagate errors to their caller. Launcher/hotkey registration awaits the shared command hook.

## Verification

`./Scripts/run-tests.sh nc-Katana-core-test` compiles the shipped Model and Service sources. The harness has fake MIDI/audio transports, synthetic pitch buffers, malformed formats, readback/save failures, private temporary library files, and stopped-operation checks. Its binary optionally accepts read-only preset paths to exercise source fixtures offline.

Physical channel/tone changes, USB capture and encoded audio files need hardware verification. No real hardware transport or audio encoder ships in this phase. No permission prompts or entitlements are added. Metronome, re-amp, Tone Exchange and system EQ remain outside this cut.

Left for the look: the island channel controls, tone library, tuner reading and recording activity views.
