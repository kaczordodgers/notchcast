# Other Mac fans

The plain Notchcast settings switch enables an on-demand client over the paired Mac Link.
It defaults off and requires Mac Link. No polling, launcher command or island page is added.

`mbp-fans` uses the version-1 `MachLinkMessage` envelope. Its JSON payload is one of
`status`, `cycle`, `auto`, `mid`, `max`. The response payload contains `mode`
(`auto`, `mid`, `max`) and `fans`, an array of 1–9 readings with `actual`, `target`,
`minimum`, `maximum` in RPM. Readings must be finite, nonnegative and at most 20,000;
maximum must exceed minimum and be at least 1,000. Manual targets must be within
25 RPM (exclusive) of the requested preset. Mid is minimum + 0.6 × (maximum − minimum).

Cycling is performed atomically by the remote helper, Auto → Mid → Max → Auto.
The client never retries a mutation on another endpoint: an ambiguous peer is rejected.
The existing Mac Link manager owns authentication, framing, correlation and timeouts.
The module serializes requests and rejects cancelled or obsolete responses.

The remote root-helper handler is pending the helper capability dependencies. The
current Mac Link listener serves AI usage only and rejects fan requests. No SMC
writes, SSH or helper installation are included here. The harness uses a fake transport
and never opens a connection. Real hardware operation remains unverified.

Reference: the existing Orion fan preset policy; no SMC implementation is copied.
