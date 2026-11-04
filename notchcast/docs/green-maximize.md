# Green button maximize

Enabled by default in Settings → Notchcast, independently of the island. Clicking the green
traffic light fills the display's visible frame in the current Space; clicking again restores
the previous frame. Option-click retains macOS behavior. Full-screen, non-resizable and excluded
apps pass through. Exclusions are comma-separated bundle identifiers in the same Settings pane.

The shared EventTapHub reads only a mutex-protected geometry snapshot. Workspace activation,
AX focused-window/move/resize notifications and a one-second refresh update that snapshot outside
the tap. Snapshots expire after two seconds. A consumed mouse down owns its matching mouse up,
even if maximizing moves the button. Queued actions validate the focused window and generation.
Stopping clears the cache, removes the tap consumer and observer, and invalidates the timer.

The pure geometry and click decisions are covered by `Tests/notchcast-green-maximize-test.swift`.
No third-party source was copied; AX access and frame writes use upstream's window-management API.
