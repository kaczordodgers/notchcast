# Shelf core

The shelf switch is off by default and requires Mac Link. No views or commands are registered.

`ShelfModule.send` accepts UTF-8 text, HTTP(S) links and binary files, up to 24 KiB each.
Names are single path components of at most 255 UTF-8 bytes. SHA-256 of kind, name and
content deduplicates received files across restarts. Every explicit send reaches the transport.
At most 64 received envelopes are retained; new items evict the oldest files by creation date.
Received JSON envelopes live in the bundle-scoped user cache, independent of temporary transport files.
They are disposable cache data, not permanent originals. Storage errors propagate to callers.

`NotchcastCore` supplies `ShelfModule.linkStatus` and `transport` through `MachLinkShelfChannel`,
which resolves the current paired endpoint at send time. The shared MachLink listener routes `shelf-item` to
`ShelfMachLinkTransport.response(to:module:)` before AI usage dispatch. It acknowledges only
after the validated item is written. The adapter is intentionally separate from link health,
which observes the same TLS link independently. Disabled or unpaired links refuse sends as peer down.

The harness uses synthetic data, a fake transport and an isolated temporary directory.
No network or other Mac is contacted. Run `./Scripts/run-tests.sh notchcast-shelf-between-macs-test`.
