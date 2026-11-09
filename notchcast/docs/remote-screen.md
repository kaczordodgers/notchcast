# Remote screen engine

The plain Remote Screen switch enables a metadata-only coordinator when Mac Link is also enabled.
The coordinator validates a DNS name, IPv4 address or IPv6 address supplied by the caller and creates
a credential-free VNC URL. It requests `remote-screen-availability` using a correlated `MachLinkMessage`.
Only availability metadata crosses that boundary; no image, clipboard, password or screen data does.

The injected client opener selects bundle ID `io.nekohasekai.screensharing` when installed, otherwise
`com.apple.ScreenSharing`. `usedFallback` exposes the fallback for a future HUD integration.
The peer answers availability through the route `RemoteScreenModule` registers: it reports its `.local` host
only while `com.apple.screensharing` is loaded (`RemoteScreenAddress.swift`). This Mac then opens the
`vnc://` URL with `NSWorkspace` (`RemoteScreenModule.swift`). The launcher command Remote Screen runs
it and reports when the switch or Screen Sharing is off on the other Mac. No screen data crosses Mac
Link. Harnesses (`nc-RemoteScreen-peer-test`, `notchcast-remote-screen-test`) use a fake channel and
opener; a real session between the Macs remains unverified.

Disabling the module invalidates pending replies. Cancellation and operation identity are checked
before opening and before applying completion. Requests and URLs remain transient and are never
persisted or logged. No streaming implementation or third-party source code is included.
