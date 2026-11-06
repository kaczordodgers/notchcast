# Approved island port status

Base: `origin/nc-design-v4-merge` at `b4953954d`. Reference: `73cb4620f`.

The launcher end capture now composes the real palette over A's silhouette, following B's `launcherEnd` composition. A's live `growIntoLauncher` already reveals the separate palette window; `showOpening` deliberately renders only the silhouette. No live reveal timing was changed. The Large and Larger fixtures now accompany Standard.

Closed fixtures add B's agents, camera, mac-update, several-items, transcribing and two-activities data through A's controller ranking. The comparison page shows both existing A visualizers at music-row and compact sizes, following B's two-row composition.

## Scope blockers

- The brief permits `Island/Pages/*`, but the actual page sources in both pinned trees are `Tinycast/Features/Notchcast/Pages/*`. S050, S053/S054 and S178–S181 require those paths and the coordinator's selection APIs. They remain unchanged.
- M15–M18: B's motion implementation depends on B's `IslandClosedState`, `IslandGeometry`, `IslandClosedView`, `IslandPieces` and `NotchcastTheme` APIs. The allowed motion/panel files cannot be copied independently. Coordinate with the closed-island builder before porting this dependency set.
- The launcher corner hairline remains unverified. No app, gallery or screenshot capture was run. The new end composition uses A's existing silhouette and does not copy B's top-edge backing band.

## Existing capture failure kinds

Examples below are relative to the supplied A/v4/gallery directory. Counts are element findings except empty AX (pages). All 165 exports explicitly report incomplete accessibility coverage. None contains clipping ancestry, so offscreen scroll descendants cannot safely be classified as visible overflow from these files alone.

| Kind | Count | Classification | JSON example / element index |
| --- | ---: | --- | --- |
| Full-canvas anonymous root AXGroup | 60 | Proven checker blind spot; exempted only at index 0 with exact canvas bounds | island-closed-airpods-ext-layout.json / 0 |
| Empty AX tree | 6 | Capture gap; middle opening is intentionally content-free, end fixture omitted palette | island-opening-end-ext-layout.json |
| Between 2x pixels | 8 | Measured geometry defect; visible impact unverified, outside changed product files | launcher-empty-dark-layout.json / 31 |
| Outside AXUnknown | 3570 | Likely scroll/document or decorative bounds; needs clipping ancestry, retained | launcher-root-dark-layout.json / 13 |
| Outside AXButton | 126 | Offscreen control; clipping unknown, retained | settings-ai-dark-layout.json / 17 |
| Outside AXScrollArea | 2 | Offscreen nested scroll region; clipping unknown, retained | settings-ai-dark-layout.json / 19 |
| Outside AXTextField | 220 | Offscreen control; clipping unknown, retained | settings-calendar-dark-layout.json / 13 |
| Outside AXMenuButton | 10 | Offscreen control; clipping unknown, retained | settings-general-dark-layout.json / 15 |
| Outside AXStaticText | 48 | Offscreen text; clipping unknown, retained | settings-general-dark-layout.json / 92 |
| Outside AXRadioGroup | 2 | Offscreen control; clipping unknown, retained | settings-notchcast-launcher-dark-layout.json / 36 |
| Outside AXRadioButton | 6 | Offscreen control; clipping unknown, retained | settings-notchcast-launcher-dark-layout.json / 37 |
| Outside AXIncrementor | 10 | Partially offscreen control; clipping unknown, retained | settings-notchcast-monitor-and-fans-dark-layout.json / 32 |

The updated checker reports 103 PASS, 62 FAIL, 165 pages, with 165 incomplete AX exports. This does not establish that the 62 remaining pages have visible product defects. No broad container, role or page exemption was added.
