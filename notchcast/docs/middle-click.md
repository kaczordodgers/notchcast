# Trackpad Middle Click

The Notchcast switch defaults on and works independently of the island. Accessibility is required.
Three-finger taps and physical presses produce middle clicks. Converted presses preserve drags and
release pairing; stopping the module releases a held middle button. Synthetic events are tagged.

This follows the Orion source variant: Three Finger Drag pauses recognition rather than moving it
to four fingers. Four-finger gestures remain available to other features. Turn off macOS's
three-finger Look Up gesture to avoid both actions responding to a tap.

EventTapHub owns physical button interception. CGEvent taps do not expose individual trackpad
contacts, so the touch adapter loads Apple's private MultitouchSupport framework at runtime.
Missing symbols or devices leave recognition inactive. No helper or additional event tap is created.
Disabling the switch stops contact callbacks and removes the hub consumer. Permission is rechecked
each second without prompting. Failed device discovery backs off for 60 seconds before retrying.
The Three Finger Drag preference is cached during the permission refresh, outside input callbacks.

The recognizer is adapted from Damian's Orion sources. No third-party implementation is copied.
Its injected clock, per-device state, movement and duration limits, typing guard, and bounce guard
are exercised by `Tests/notchcast-middle-click-test.swift`.
