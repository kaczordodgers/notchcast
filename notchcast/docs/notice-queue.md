# Island notice queue

All transient notices enter `IslandActivityCenter.showMessage`, including treadmill,
accessory, system and routed HUD messages. The visible notice keeps its original dwell;
waiting notices display in arrival order for their own dwell. Eight waiting slots are kept,
dropping the oldest waiting notice on overflow without interrupting the visible one.

A duplicate waiting ID updates content and duration in its existing slot. Callers may supply
an ID; otherwise the text identifies the notice. Progress retains its existing replacement
behavior. Explicit dismissal clears waiting notices too, including when HUD routing stops.
No view or display styling changes.

`Tests/notchcast-notice-queue-test.swift` exercises the shipped center with an injected
clock and a recording fake presenter, without hardware events or real notifications.
