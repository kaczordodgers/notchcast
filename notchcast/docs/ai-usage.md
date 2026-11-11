# AI usage and Mac link

The `aiUsage`, `aiUsageOtherMac` and `machLink` switches default off. They do not depend on Island.
Our features live in a Notchcast category in the Settings sidebar, one tab per module. Every switch has a working function, and its commands sit under it. Turning a switch off removes its commands.
The other-Mac switch is effective only while AI usage and Mac link are enabled: its descriptor lists both as dependencies, and the requester and the `ai-usage` route both ask `isEnabled(.aiUsageOtherMac)`.

`AIUsageModule.refresh()` reads the local cache on demand. Starting a module does not read it, and
there is no refresh timer. The provider accepts an injected directory and clock for fixture tests.
An empty cache path resolves to `~/.t3/caches` at refresh time; an explicit path wins.
Local snapshots retain optional reset credits (`availableCount`); malformed credits are ignored.
`AIUsageSnapshotAdapter` projects provider windows into the peer engine's normalized wire readings;
the wire representation intentionally carries no provider-specific display or reset metadata.

`MachLink/AIUsageLinkModule` owns the listener and browser. Switching Mac link off stops both and cancels
incoming work. `MachLinkChannel+OtherMacUsage.swift` registers the `ai-usage` route; incoming requests require that rule to hold before and after reading a local
snapshot. Outbound peer requests retain the engine's one-minute minimum interval.

Enable Mac link on both Macs. Pair with an empty code on one Mac, then enter that code and Pair on
the other. The code contains the shared authentication secret: transfer it privately. The app stores
the secret in its bundle-scoped Keychain service and only its identifier in fork-local defaults.
Unpair removes that secret. Pairing codes are never included in settings backups or logs.

`Tests/notchcast-l5-ai-usage-wire-test.swift` covers default-off lifecycle, a fixture read, a missing
peer, a real loopback peer response, child dependency changes and teardown. Physical two-Mac pairing
and Settings rendering require integration verification.

## Local network validation

Local-network privacy may require `NSLocalNetworkUsageDescription` and `NSBonjourServices`.
Verify discovery and pairing on two Macs before shipping; Info.plist changes are deferred.
