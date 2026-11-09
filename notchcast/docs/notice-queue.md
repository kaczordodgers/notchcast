# Island notice queue

`IslandActivityCenter.showMessage` takes an optional `id`, and only notices that pass one wait their turn.

- **With an `id`** (fork notice sources: treadmill goal and lube, per-accessory connection and low battery, low disk, Wi-Fi, Tailscale, battery, the other Mac's blocked dialog): if nothing is up the notice shows at once; otherwise it waits in arrival order and shows for its own dwell when the visible one ends. A waiting notice with the same `id` updates its slot in place; one matching the visible `id` updates the visible notice in place and re-arms its dwell, so it never shows twice. Eight waiting slots are kept, dropping the oldest waiting notice on overflow. An `id` notice waits behind a progress pill rather than replacing it.
- **Without an `id`** (every upstream HUD call, every remote notice and result, the dictation pill): the message shows at once, replacing the visible message or progress pill in place and re-arming the dwell, exactly as upstream's HUD does. When its dwell ends the queue resumes.
- **Routing**: every notice enters through `IslandHUDRouter`. Upstream's HUD routes only when a presenter shows the island and `islandStatusMessages` is on; `post` always enters the center, as fork notices did, and returns nil when no presenter shows it, so a remote result falls back to the HUD.
- **Dismissal** (`dismiss(_:)`): `showMessage` and `showProgress` return a `NoticeHandle`, and only that handle ends its notice. A visible notice ends and the next waiting one shows; a waiting one leaves the queue; a notice another poster already replaced is left alone. Upstream's `hideProgress` ends only the HUD's own notice, so the dictation pill and a remote result stay up, though a new HUD message still replaces whatever is visible. The queue is never dropped.
- The `id` is the update key that slots and replaces a notice; the handle only identifies who may end it.

No view or display styling changes.

`Tests/notchcast-notice-queue-test.swift` exercises the shipped center with an injected clock, without hardware events or real notifications.
