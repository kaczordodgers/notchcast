import SwiftUI

/// The island kit: every size, colour, type and motion value island and page views read, on Tinycast's own `Theme`
/// wherever Tinycast has the value (`notchcast/docs/rules`: the closed island is the launcher's search row shrunk to a
/// black capsule; opening grows it into the launcher). Island and page code reads these, never a literal
/// (`notchcast/check-kit.py`).
enum NotchcastTheme {
    /// Every closed row is the launcher's search row: the island capsule, the strip under the camera, the bubble.
    static let rowHeight = Theme.Size.headerHeight
    static let statusHeight = rowHeight
    static let statusRadius = rowHeight / 2
    /// A compact `BarButton`'s glyph: the size that makes it a square as tall as the bar.
    static let headerGlyph = Theme.Size.noteGlyph
    /// The island at rest: a capsule as wide as Orion's resting pill, as tall as the search row, under the top edge.
    static let monitorPill = CGSize(width: 180, height: rowHeight)
    static let openMinimumWidth: CGFloat = 800
    static let estimatedContentHeight: CGFloat = 96
    static let monitorHeader = Theme.Size.headerHeight
    static let maximumHeight = Theme.Size.panelHeight
    static let openRadius = Theme.Radius.panel
    static let closedRadius = Theme.Radius.row
    static let closedShoulder = Theme.Radius.thumbnail
    static let openShoulder = Theme.Radius.row
    /// A notch wing holds one piece (a cover, the bars, a glyph) with the row's inset either side.
    static let minimumWing: CGFloat = 44

    /// The silhouette's corners follow its height, so a strip as tall as the camera keeps the cutout's own small
    /// corners and the open island reaches the caps (rule: `IslandSilhouette.shoulder` / `bottomRadius`).
    enum Corners {
        /// The concave flare where the island meets the screen's top edge, at its widest.
        static let shoulderCap: CGFloat = 14
        /// The open island and the launcher grown from it share the palette's corner.
        static let radiusCap = Theme.Radius.panel
        static func shoulder(height: CGFloat) -> CGFloat {
            IslandSilhouette.shoulder(height: height, cap: shoulderCap)
        }
        static func bottomRadius(height: CGFloat) -> CGFloat {
            IslandSilhouette.bottomRadius(height: height, cap: radiusCap)
        }
        static let artwork = Theme.Radius.thumbnail
    }

    /// The closed pill on a monitor: a capsule under the top edge; beside a notch the band is the notch's height.
    enum Pill {
        /// The gap under the top edge (Orion, 2 Nov: the menu title highlight sits 4 pt from the top).
        static let topGap = Theme.Spacing.xs
        /// The HUD pill's own inset.
        static let inset = Theme.Spacing.xl
        /// The launcher's row icon.
        static let artwork = Theme.Size.resultRowIcon
        /// Glyph or cover to its text: one gap in every line (the launcher's icon-to-name gap).
        static let artworkGap = Theme.Spacing.md
        static let glyph = Theme.Size.menuIcon
        /// The symbol in that slot: the menu row's; the HUD pill too draws text-sized marks in it.
        static let symbol = Theme.Typography.menuSymbolSize
        /// Text to its value or bars: a row's trailing gap.
        static let gap = Theme.Spacing.lg
        /// The level readout's fixed slot, so 9% and 100% keep the pill still.
        static let readout = Theme.Size.volumeReadout
        /// The track text runs to here, then scrolls (Orion's pill text limit).
        static let textLimit: CGFloat = 196
        /// A second activity's round bubble: a row's height, a row's gap to its right (Orion's bubble, 6 pt).
        static let bubble = rowHeight
        static let bubbleGap = Theme.Spacing.sm
        /// The scrolling title's pace and its rest at each end.
        static let scrollSpeed: CGFloat = 30
        static let scrollRest: TimeInterval = 1.2
    }

    /// A card's button: the footer's action group, a bar button held `xs` inside a row-high capsule.
    enum Card {
        static let button = Theme.Size.barButtonHeight
        static let inset = Theme.Spacing.md
        /// The capsule's end past the button, as wide as the gap above it, so the two ends are concentric.
        static let trailing = Theme.Spacing.xs
    }

    /// The level beside a playing song: Orion's four bars (`LevelBars`), white.
    enum MusicBars {
        static let count = 4
        static let width: CGFloat = 3
        static let gap = Theme.Spacing.xxs
        static let height: CGFloat = 14
        /// A paused level rests at this share of `height`; the lowest a moving bar dips.
        static let restingLevel = 0.6
        static let lowestLevel = 0.3
        static let cycle: TimeInterval = 0.9
        static let delays: [TimeInterval] = [0, -0.35, -0.6, -0.15]
    }

    /// Damian Tools' spectrum (`NotchBars`): seven bars on a Winamp fall, a dot each at rest, drawn at the level
    /// bars' own stroke and gap so the two candidates compare at one size.
    enum SpectrumBars {
        static let count = 7
        static let width = MusicBars.width
        static let gap = MusicBars.gap
        static let height = MusicBars.height
        static let peakHeight: CGFloat = 1
        static let peakGap: CGFloat = 1
    }

    /// An open page that is not the launcher. No width token: each page is as wide as its own content,
    /// never another page's or the morph's width (look-decisions, 3 Nov 23:21).
    enum Open {
        static let headerHeight = Theme.Size.headerHeight
        static let pageInset = Theme.Spacing.md * 2
        static let sectionGap = Theme.Spacing.sectionSpacing
    }

    /// The launcher grown from the island keeps the palette's own geometry.
    enum Launcher {
        static let size = CGSize(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight)
        static let radius = Theme.Radius.panel
        static let header = Theme.Size.compactHeight
        static let rowPitch = Theme.Size.resultRowIcon + Theme.Spacing.sm * 2
        static let listInset = Theme.Spacing.md
        static let footer = Theme.Size.bottomBarHeight
        static let footerCapsule = Theme.Size.menuButton
    }

    /// macOS text styles at the sizes the references set: callout is 12 pt, subheadline 11 pt.
    enum Typography {
        /// The bar's own weight: hierarchy over the artist comes from colour, not a heavier face.
        static let pillTitle = Theme.Typography.bar
        static let pillSubtitle = Font.subheadline
        static let activityValue = Theme.Typography.rowTrailing
        static let activityWord = Theme.Typography.bar
        static let pageName = Theme.Typography.bar
    }

    /// The island is drawn dark in every appearance, so its ink is the ramp's dark side.
    enum Colors {
        /// The hardware notch's own black, so the closed island disappears into it and into a black menu bar.
        static let surface = Color.black
        static let primary = Theme.Colors.textPrimary
        static let secondary = Theme.Colors.textSecondary
        static let tertiary = Theme.Colors.textTertiary
        static let selection = Theme.Colors.selection
        /// A card's button and a value chip: Tinycast's small control surface and its hover step.
        static let control = Theme.Colors.controlSurface
        static let controlHover = Theme.Colors.controlHover
        /// The square a missing album cover leaves, the row icon's own placeholder.
        static let placeholder = Theme.Colors.iconPlaceholder
        /// Only an error and a warning carry colour in a closed state (look-decisions, Messages).
        static let danger = Theme.Colors.destructive
        static let warning = Theme.Colors.warning
    }

    /// The silhouette moves on springs; content and the black fade on Tinycast's surface durations.
    enum Motion {
        static let pageChange = Animation.easeOut(duration: Theme.Duration.hover)
        /// Opening, and a closed row changing shape: no bounce, since a notch island must never dip under the notch.
        static let grow = Spring(duration: Theme.Duration.settingsReveal, bounce: 0)
        static let shrink = Spring(duration: Theme.Duration.enter, bounce: 0)
        static let contentIn = Theme.Duration.dialogEnter
        static let contentOut = Theme.Duration.exit
        /// An outgoing closed row holds one beat over the new one, so pieces both show never dim.
        static let contentHold = Theme.CompactBarMotion.stagger
        /// After a close the closed row waits for the island to land, as a summon lands first.
        static let landing = Theme.CompactBarMotion.revealDelay
        static let blackOut = Theme.Duration.exit
        static let blackIn = Theme.Duration.enter
    }
}
