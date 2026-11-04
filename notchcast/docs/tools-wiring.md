# Tools switches

Cleaning Mode, App Updates and Update this Mac default to off in fork preferences.
Enabling them does no work until Start, Check or Run is pressed. Disabling cancels
work and discards pending results. Cleaning requires Accessibility, exits on five
Escape presses and has an independent 300-second deadline with a one-second health poll.
App Updates uses the engine's private ephemeral transport and only displays results.
Update this Mac requires a dialog listing its steps and offers cancellation.

The wiring harness uses injected transports, an injected event registration and a
fake process runner. It never performs maintenance or registers a real event tap.
