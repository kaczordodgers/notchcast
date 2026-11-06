# Link health

The Link Health switch defaults off and requires Mac Link. It polls an authenticated
`link-health` heartbeat every 60 seconds, with a two-second timeout per endpoint
and at most two discovered endpoints per poll. It does not read AI usage.

Two consecutive failures mark the peer down and emit one loss notice. Two consecutive
successes mark it up; recovery emits one notice only after a down state. Alternating
results preserve the previous reachability. Initial success is silent; initial failure
is reported after the second failed probe. Notices use a `post: @MainActor (String) -> Void`
closure wired to the existing island activity center and respect its status-message preference.

Consumers can observe `NotchcastCore.linkHealth.health`: `reachability` is unknown,
up or down; `latency` is the latest successful heartbeat round trip (nil after a failure);
`lastSeen` is the date of the last successful probe. `isRunning` distinguishes disabled
monitoring. Stopping resets the snapshot and cancels polling; late results are discarded.

This measures the paired MachLink peer only. Cable routing, mirror freshness and
external control-plane state are outside this implementation. No address is compiled in.
Live checks between Macs remain manual; the harness uses synthetic data.
