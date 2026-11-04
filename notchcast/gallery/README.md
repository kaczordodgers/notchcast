# Offscreen gallery

Run `notchcast/gallery/snap.sh [--out <empty-directory>]`. It builds a Debug app
through `~/chad/bin/build-queue.py` when available, otherwise `xcodebuild`. Build
products, the disposable home and helper executables stay in a unique
`~/agents/nc-design/gallery.XXXXXX` directory. `--app <Debug.app>` or
`NOTCHCAST_GALLERY_APP` reuses a previously built gallery app.
`NOTCHCAST_GALLERY_DERIVED_DATA` reuses an existing scratch build directory for
the next incremental build, avoiding a second full build on a small disk.

One output folder contains PNGs at 2x, matching `*-layout.json`, `manifest.txt`,
`coverage.json`, `inventory.json`, `inventory.md`, `run.log` and `layout-check.log`.
The manifest is written before rendering. Missing PNGs or layout files, capture
errors and offscreen-check failures make the command fail. Layout findings are
reported independently: `python3 notchcast/gallery/check-layout.py <out>` exits
nonzero for findings. They do not modify the product or suppress successful captures.

Stable page names:

- `island-closed-{idle,timer,transfer,status}-{mba,ext}`
- `island-open-{home-empty,home-entries,day-calendar}-{mba,ext}`
- `launcher-{root,results,empty}-{dark,light}`
- `settings-notchcast-<group>-{dark,light}`
- `settings-<SettingsTab.slug>-{dark,light}` (including hidden upstream tabs)

The MBA fixture is 1470 × 956 with a centered 184 × 32 hardware notch; the
external fixture is 1920 × 1080. Island images use the real panel and its real
surface, closed view, content wrapper and silhouette. Day uses the real schedule
list with fake events, without loading EventKit. Launcher fixtures use the real
palette root, search field and launcher list. The first registry does not yet cover every palette state,
window or editor. `inventory.md` lists gaps by area for subsequent registries.

Each area owns `GalleryPages+<Area>.swift`. Register explicit view types with each
page; do not claim conditional children that the fixture does not render.
`inventory.py` scans every Swift UI declaration in `Tinycast/`; newly added types
appear as gaps automatically. Settings detail pane membership is read from the
shipped switch. A listed view does not imply every possible state is covered.

`CFFIXED_USER_HOME` and `HOME` must point to the same marked disposable home.
The early Debug launch hook bypasses normal startup, menu extras, onboarding,
hotkeys and module startup. The runner additionally denies network access,
Keychain service access and reads/writes under the real home except scratch and
the supplied app. It never launches the installed copy, orders a window or
activates an app. The independent WindowServer/process monitor checks the run
and descendants for visible windows and focus changes. It cannot observe a
window shorter than its 100 ms sample interval; absence of WindowServer is an
error, never a pass. No sleep-prevention or user-activity assertion is made.

Layout coordinates are AppKit bottom-left points within the canvas. The JSON
records raw accessibility frames and roles/labels, the silhouette bounding
rectangle, hardware notch and canvas. Accessibility-hidden decoration is absent
by design. The checker tests containment, hardware-notch overlap for closed MBA
content, and all four edges on the 2x pixel grid. Container frames may span the
hardware notch; content frames may not. It does not round measurements or repair
existing UI defects. Run its fixtures with
`python3 notchcast/gallery/check-layout-test.py`.

Known AX gap: every current `island-closed-*-{mba,ext}`,
`island-open-*-{mba,ext}`, `launcher-*-{dark,light}`,
`settings-notchcast-*-{dark,light}` and `settings-*-{dark,light}` page has an
incomplete export. SwiftUI omits virtual accessibility children when its window
has never been ordered. Every element AX actually exposes is retained alongside
the canvas, silhouette and hardware notch; measurements are not invented. Each
layout declares `accessibilityComplete: false`; `inventory.json` and
`inventory.md` enumerate the affected page names. A passing layout check validates
only the exposed frames. Header keyboard focus and alternate per-feature states
also remain gaps, even where a view type already has a registered page.

Liquid Glass requires the window compositor and cannot render offscreen. These
PNGs retain the real controls but cannot represent live glass refraction; no
replacement glass effect is drawn.
