# Remote screen engine

The plain Remote Screen switch enables a metadata-only coordinator when Mac Link is also enabled.
The coordinator validates a DNS name, IPv4 address or IPv6 address supplied by the caller and creates
a credential-free VNC URL. It requests `remote-screen-availability` using a correlated `MachLinkMessage`.
Only availability metadata crosses that boundary; no image, clipboard, password or screen data does.

The injected client opener selects bundle ID `io.nekohasekai.screensharing` when installed, otherwise
`com.apple.ScreenSharing`. `usedFallback` exposes the fallback for a future HUD integration.
The app module holds the existing Mac Link channel but deliberately returns unavailable: real
transport routing, availability responder and client launching are deferred. No network or screen
sharing is initiated by this module. The harness supplies fake transport and opener implementations.

Disabling the module invalidates pending replies. Cancellation and operation identity are checked
before opening and before applying completion. Requests and URLs remain transient and are never
persisted or logged. No streaming implementation or third-party source code is included.
