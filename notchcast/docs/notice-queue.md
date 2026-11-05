# Island notice queue

`IslandActivityCenter.showMessage` takes an optional `id`, and only notices that pass one wait their turn.

- **With an `id`** (fork notice sources: treadmill goal and lube, per-accessory connection and low battery, low disk, Wi-Fi, Tailscale, battery, the other Mac's blocked dialog): if nothing is up the notice shows at once; otherwise it waits in arrival order and shows for its own dwell when the visible one ends. A waiting notice with the same `id` updates its slot in place; one matching the visible `id` updates the visible notice in place and re-arms its dwell, so it never shows twice. Eight waiting slots are kept, dropping the oldest waiting notice on overflow. An `id` notice waits behind a progress pill rather than replacing it.
- **Without an `id`** (every upstream HUD call routed by `IslandHUDRouter`, and remote notices): the message shows at once, replacing the visible message or progress pill in place and re-arming the dwell, exactly as upstream's HUD does. When its dwell ends the queue resumes.
- **Dismissal** (`dismissMessage`, e.g. a quick action hiding its progress pill, or HUD routing stopping) clears only the visible message and then presents the next waiting notice; the queue is never dropped.

No view or display styling changes.

`Tests/notchcast-notice-queue-test.swift` exercises the shipped center with an injected clock, without hardware events or real notifications.
