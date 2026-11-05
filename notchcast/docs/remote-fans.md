# Other Mac fans

The plain Notchcast settings switch enables an on-demand client over the paired Mac Link.
It defaults off and requires Mac Link. The launcher command Other Mac Fans cycles the mode and
reports the result; there is no polling or island page.

`mbp-fans` uses the version-1 `MachLinkMessage` envelope. Its JSON payload is one of
`status`, `cycle`, `auto`, `mid`, `max`. The response payload contains `mode`
(`auto`, `mid`, `max`) and `fans`, an array of 1–9 readings with `actual`, `target`,
`minimum`, `maximum` in RPM. Readings must be finite, nonnegative and at most 20,000;
maximum must exceed minimum and be at least 1,000. Manual targets must be within
25 RPM (exclusive) of the requested preset. Mid is minimum + 0.6 × (maximum − minimum).

Cycling is performed by the peer, Auto → Mid → Max → Auto.
The client never retries a mutation on another endpoint: an ambiguous peer is rejected.
The existing Mac Link manager owns authentication, framing, correlation and timeouts.
The module serializes requests and rejects cancelled or obsolete responses.

The peer answers `mbp-fans` through `MachLinkManager+Peers.swift` with its one existing
`MonitorModule` fan control (`MachMBPFans/RemoteFanPeer.swift`): same limits, and it refuses
unless Mac Link, System Monitor and Fan Control are all on there. It applies the mode, reads
the fans over SMC and reports busy if the mode changed meanwhile. Harnesses
(`nc-MachMBPFans-peer-test`, `notchcast-remote-fans-test`) use a fake channel and fake fans.
Real hardware operation between the Macs remains unverified.

Reference: the existing Orion fan preset policy; no SMC implementation is copied.
