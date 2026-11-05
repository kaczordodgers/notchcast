# Green button maximize

Enabled by default in Settings → Notchcast, independently of the island. Clicking the green
traffic light fills the display's visible frame in the current Space; clicking again restores
the previous frame. Option-click retains macOS behavior. Full-screen, non-resizable and excluded
apps pass through. Exclusions are comma-separated bundle identifiers in the same Settings pane.

The shared EventTapHub reads mutex-protected button snapshots for all running applications, including non-focused windows. A serial background queue reads AX windows and hit-tests each button's center to exclude covered buttons; no AX call blocks the tap. Workspace activation and a one-second timer refresh the snapshots, with requests coalesced and results discarded after stop. Snapshots expire two seconds after the read starts. A consumed mouse down owns its matching mouse up, even if maximizing moves the button. Queued actions validate the module generation and act on the captured window, independently of application focus. Stopping clears the snapshots, removes the consumer and invalidates the timer.

Newly exposed or moved buttons can pass through until the next refresh. The macOS green-button hover popup is outside this click-only feature.

The pure geometry and click decisions are covered by `Tests/notchcast-green-maximize-test.swift`.
No third-party source was copied; AX access and frame writes use upstream's window-management API.
