# Green button maximize

Enabled by default in Settings → Notchcast, independently of the island. Clicking the green
traffic light fills the display's visible frame in the current Space; clicking again restores
the previous frame. Option-click retains macOS behavior. Full-screen, non-resizable and excluded
apps pass through. Exclusions are comma-separated bundle identifiers in the same Settings pane.

The shared EventTapHub reads mutex-protected button snapshots for applications owning on-screen layer-0 windows, excluding prohibited applications. A serial queue reads AX windows in CGWindowList application order and hit-tests each button's center. Before consuming a click, a live AX hit test with a 10 ms messaging timeout must identify the captured button; this also resolves overlapping windows within an application. Frontmost-app window notifications, workspace activation, passed-through mouse downs and a one-second timer refresh snapshots. Notifications clear cached targets immediately. Requests coalesce and results are discarded after stop. Snapshots expire after two seconds. A consumed mouse down owns its mouse up. Queued actions validate the module generation and act on the captured window. Stopping removes the observer, consumer and timer.

Newly exposed or moved buttons can pass through until the next refresh. The macOS green-button hover popup is outside this click-only feature.

The pure geometry and click decisions are covered by `Tests/notchcast-green-maximize-test.swift`.
No third-party source was copied; AX access and frame writes use upstream's window-management API.
