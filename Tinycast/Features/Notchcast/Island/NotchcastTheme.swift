import SwiftUI

/// The island kit: every size, colour, type and motion value island and page views read, measured from the
/// references or taken from source, and on Tinycast's own `Theme` wherever Tinycast has the value.
/// Island and page code reads these, never a literal (`notchcast/check-kit.py`).
enum NotchcastTheme {
    static let statusHeight: CGFloat = 36
    static let statusRadius: CGFloat = 18
    static let headerGlyph: CGFloat = 16
    static let monitorPill = CGSize(width: 180, height: Theme.Size.barButtonHeight)
    static let openMinimumWidth: CGFloat = 800
    static let estimatedContentHeight: CGFloat = 96
    static let monitorHeader = Theme.Size.headerHeight
    static let maximumHeight = Theme.Size.panelHeight
    static let openRadius = Theme.Radius.panel
    static let closedRadius = Theme.Radius.row
    static let closedShoulder = Theme.Radius.thumbnail
    static let openShoulder = Theme.Radius.row
    static let minimumWing: CGFloat = 44
    /// The Home list's height allowance per activity row, kept until Home is redesigned.
    static let homeActivityRow: CGFloat = 56

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

    /// The closed pill: on a monitor it floats under the top edge; beside a notch it is the notch's height.
    enum Pill {
        /// A monitor pill's height when the menu bar reads none; two lines of song need it.
        static let fallbackHeight: CGFloat = 30
        // No width token: the pill is as wide as its content (insets + artwork + gap + text + bars).
        static let topGap = Theme.Spacing.xs
        static let inset = Theme.Spacing.xl
        static let artwork = fallbackHeight - Theme.Spacing.xs * 2
        static let artworkGap = Theme.Spacing.md
        static let glyph = Theme.Size.menuIcon
    }

    /// The music level beside a playing song.
    enum MusicBars {
        static let count = 4
        static let width: CGFloat = 3
        static let gap = Theme.Spacing.xxs
        static let height: CGFloat = 14
        /// A paused level rests at this share of `height`.
        static let restingLevel = 0.6
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
        static let pillTitle = Font.callout.weight(.semibold)
        static let pillSubtitle = Font.subheadline
        static let activityValue = Theme.Typography.rowTrailing
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
        static let tile = Theme.Colors.cardFill
    }

    /// Tinycast's glass morph, for controls that bead out of the island.
    enum Motion {
        static let capsule = Theme.CompactBarMotion.capsule
        static let button = Theme.CompactBarMotion.button
        static let pageChange = Animation.easeOut(duration: Theme.Duration.hover)
    }
}
