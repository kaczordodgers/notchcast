# Shelf core

The shelf switch is off by default and requires Mac Link. No views or commands are registered.

`ShelfModule.send` accepts UTF-8 text, HTTP(S) links and binary files, up to 24 KiB each.
Names are single path components of at most 255 UTF-8 bytes. SHA-256 of kind, name and
content deduplicates sends within a running session and receives across restarts.
At most 64 received envelopes are retained; a full store refuses further items without eviction.
Received JSON envelopes live in the bundle-scoped user cache, independent of temporary transport files.
They are disposable cache data, not permanent originals. Storage errors propagate to callers.

Integration supplies `ShelfModule.linkStatus` using the folder-local `ShelfLinkStatus` protocol
and sets `transport` to `ShelfMachLinkTransport` for the current paired endpoint.
The shared MachLink listener must route method `shelf-item` to
`ShelfMachLinkTransport.response(to:module:)` before AI usage dispatch. It acknowledges only
after the validated item is written. The adapter is intentionally separate from link health,
which is built by another worker. Until these connections are supplied, sends refuse as peer down.

The harness uses synthetic data, a fake transport and an isolated temporary directory.
No network or other Mac is contacted. Run `./Scripts/run-tests.sh notchcast-shelf-between-macs-test`.
