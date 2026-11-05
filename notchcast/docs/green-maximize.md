# Green button maximize

Enabled by default in Settings → Notchcast, independently of the island. Clicking the green
traffic light fills the display's visible frame in the current Space; clicking again restores
the previous frame. Option-click retains macOS behavior. Full-screen, non-resizable and excluded
apps pass through. Exclusions are comma-separated bundle identifiers in the same Settings pane.

The shared EventTapHub reads only a mutex-protected geometry snapshot. Workspace activation,
AX focused-window/move/resize notifications and a one-second refresh update that snapshot outside
the tap on a serial background queue, including observer registration. Refresh requests coalesce;
results are discarded after stop or a front-app change. AX handles transfer to main only after the
worker finishes. Snapshots expire two seconds after the read starts. A consumed mouse down owns its matching mouse up,
even if maximizing moves the button. Queued actions validate snapshot age and lifecycle generation.
Stopping clears the cache, removes the tap consumer and observer, and invalidates the timer.

The tap also consumes pointer motion over the green button to prevent its hover tile menu.
An intercepted press owns dragging and release even after the button moves. Option bypasses
hover and press interception. AX discovery prefers a valid zoom button frame, then a
valid full-screen button frame; empty or disabled controls cannot shadow the usable control.

Pointer discovery has its own serial queue so a hung app cannot block frontmost refreshes.
Main reads on-screen layer-0 window bounds through CGWindowListCopyWindowInfo before pointer AX.
Only their top-left 100×40 pt zones qualify: three observed 16 pt buttons plus gaps and margins
fit within 100 pt, with 40 pt covering the title-bar height. Outside these zones the pointer
snapshot clears and no pointer AX read runs, including on the idle timer. The tap checks cached
geometry only and hops to main when zone membership changes, coalescing motion within a zone.
The window under the
pointer supplies a second snapshot, including its exact AX handle and pid, so background traffic
lights work without activating the app first. Actions target the captured window rather than
requiring the focused window; stop invalidates both snapshots. Pointer snapshots have the same
two-second expiry and exclusions. Hover suppression remains confined to a matching button rect.

The pure geometry and click decisions are covered by `Tests/notchcast-green-maximize-test.swift`.
No third-party source was copied; AX access and frame writes use upstream's window-management API.
