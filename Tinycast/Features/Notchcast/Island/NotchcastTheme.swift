import SwiftUI

/// The island kit: every size, colour, type and motion value island and page views read, measured from the
/// launcher or taken from source, and on Tinycast's own `Theme` wherever Tinycast has the value.
/// Island and page code reads these, never a literal (`notchcast/check-kit.py`). The rule sheet behind the
/// closed states and the opening is `notchcast/docs/island-closed.md`.
enum NotchcastTheme {
    static let headerGlyph: CGFloat = 16
    static let openMinimumWidth: CGFloat = 800
    static let estimatedContentHeight: CGFloat = 96
    static let monitorHeader = Theme.Size.headerHeight
    static let maximumHeight = Theme.Size.panelHeight
    static let openRadius = Theme.Radius.panel
    static let openShoulder = Theme.Radius.row

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

    /// Every closed state of both shapes: one row height, one set of insets, one type ramp.
    enum Closed {
        /// The island pill and every row below the camera: the launcher's search row, menu-bar high (Damian, 2 and
        /// 5 Nov), so both shapes and the launcher share one row.
        static let row = Theme.Size.headerHeight
        /// The island floats this far under the screen's top edge (Orion, 2 Nov).
        static let topGap = Theme.Spacing.xs
        /// An idle island: four of its heights, a pill and not a dot.
        static let idleWidth = row * 4
        /// A cover is a launcher row's icon, round in the capsule's end.
        static let artwork = Theme.Size.resultRowIcon
        static let glyph = Theme.Size.menuIcon
        /// The mark inside that slot: 16, not the menu row's 14, which read thin beside a 17-point value on the notch
        /// (Damian, v3 review). The one place a component token departs from the semantic one.
        static let symbol = Theme.Size.menuIcon * 0.8
        /// Gap from the leading item to its text, and the least gap before the trailing item.
        static let itemGap = Theme.Spacing.md
        static let trailingGap = Theme.Spacing.xl
        /// Text and bars sit this far from an end cap; a cover or glyph is centred on the cap instead.
        static let textInset = Theme.Spacing.md
        /// The title's width limit before it scrolls, as a source chip's title truncates.
        static let titleLimit = Theme.Size.chatSourceTitle
        static let maximumWidth = Theme.Size.hudMaxWidth
        /// The bubble beside the island for the second thing, a compact-bar button's distance away.
        static let bubble = row
        static let bubbleGap = Theme.Spacing.sm
        /// A notch wing holds a glyph with `xl` either side, and grows with its content.
        static let wing = Theme.Size.menuIcon + Theme.Spacing.xl * 2
        static let wingInset = Theme.Spacing.xl + Theme.Spacing.sm / 2
        static let contentInset = Theme.Spacing.lg
        static let wingTextLimit: CGFloat = 100
        static let shoulder = Theme.Radius.thumbnail
        /// Rows below the camera: `sm` under the last.
        static let dropBottom = Theme.Spacing.sm
        static let lineSpacing: CGFloat = 0
        /// A card's button: a capsule concentric with the pill's end (18 − 5 = 13, half of 26).
        static let button = Theme.Size.resultRowIcon
        static let buttonInset = Theme.Spacing.md
        /// The scrolling title: its pause at each end, its speed and the gap before it repeats.
        static let scrollPause: TimeInterval = 1.6
        static let scrollSpeed: CGFloat = 24
        static let scrollGap = Theme.Spacing.xxxl
    }

    /// The value type's marks.
    enum Value {
        static let ring = Theme.Size.chatContextGauge
        static let ringStroke = Theme.Size.contextRingStroke
        static let dot = Theme.Size.colorDot
    }

    /// The AI usage page: a row per account, its windows in fixed columns so the bars line up down the page.
    /// Name, gap and three windows (150 + 12 + 3 × 190 + 2 × 12 = 756) fit the open island's 800 with its insets.
    enum Usage {
        static let nameColumn: CGFloat = 150
        static let windowColumn: CGFloat = 190
        static let columnGap = Theme.Spacing.xl
        static let lineGap = Theme.Spacing.xxs
        static let bar = Theme.Spacing.xs
        /// "100% left" at the value size, so the bars keep one length whatever the number.
        static let percentColumn: CGFloat = 58
        /// Under this share left a window takes the warning hue and a mark; at none, the error hue.
        static let lowLeft = 20
        /// A reading older than this, or one Magpie answered from cache, is dimmed and says when it was read.
        static let staleAfter: TimeInterval = 15 * 60
        static let staleOpacity = 0.5
    }

    /// The two visualizers Damian chooses between: Orion's and Damian Tools'.
    enum Visualizer {
        static let height: CGFloat = 14
        /// Orion's bars until Damian picks: he liked how they looked (look-decisions, "bar follows the music").
        static let closedStyle = IslandVisualizer.Style.orion
        enum Orion {
            static let count = 4
            static let width: CGFloat = 3
            static let gap = Theme.Spacing.xxs
            static let restingLevel = 0.6
            static let lowestLevel = 0.3
            static let cycle: TimeInterval = 0.9
            static let offsets: [TimeInterval] = [0, -0.35, -0.6, -0.15]
        }
        enum Analyser {
            static let count = 7
            static let width: CGFloat = 1.8
            /// Centre to centre, as a share of a bar's width.
            static let pitch: CGFloat = 1.85
            static let peak: CGFloat = 1
            static let peakGap: CGFloat = 1
        }
        /// The debug lab's tiles.
        static let labTile = CGSize(width: Theme.Size.dialogCompactWidth, height: Theme.Size.hudHeight)
    }

    /// The launcher grown from the island keeps the palette's own geometry, read the way the palette reads it:
    /// at the current interface size, so at Large and Larger the opening ends on the launcher's real frame and corner.
    @MainActor enum Launcher {
        static var metrics: InterfaceMetrics { AppCore.shared.settings.interfaceSize.metrics }
        static var size: CGSize { CGSize(width: metrics.size.panelWidth, height: metrics.size.panelHeight) }
        /// The palette's clip (`RootPaletteView`, `metrics.radius.panel`): 26, 29 at Large, 31 at Larger.
        static var radius: CGFloat { metrics.radius.panel }
        /// The island panel's width, wide enough for the launcher and the shoulders it hangs from the notch by, at
        /// every interface size (845 at Large and 920 at Larger pass the open island's 800).
        static var canvasWidth: CGFloat { max(openMinimumWidth, size.width + openShoulder * 2) }
    }

    /// macOS text styles: callout is 12 pt, subheadline 11 pt.
    enum Typography {
        static let title = Theme.Typography.bar
        static let detail = Font.subheadline
        static let value = Theme.Typography.rowTrailing
    }

    /// The island is drawn dark in every appearance, so its ink is the ramp's dark side. Everything is white for
    /// now; only error and warning take a hue.
    enum Colors {
        /// The hardware notch's own black, so the closed island disappears into it and into a black menu bar.
        static let surface = Color.black
        static let primary = Theme.Colors.textPrimary
        static let secondary = Theme.Colors.textSecondary
        static let tertiary = Theme.Colors.textTertiary
        static let control = Theme.Colors.controlSurface
        static let controlHover = Theme.Colors.controlHover
        static let controlPressed = Theme.Colors.controlPressed
        static let warning = Theme.Colors.warning
        static let error = Theme.Colors.destructive
        /// Layer-drawn bars resolve no appearance, and the island is always dark, so their ink is plain white.
        static let barInk = NSColor.white
        /// `surface` for the layer the silhouette masks.
        static let surfaceInk = NSColor.black
    }

    enum Motion {
        static let pageChange = Animation.easeOut(duration: Theme.Duration.hover)
        /// A closed state's content swapping in place.
        static let swap = Animation.easeOut(duration: Theme.Duration.hover)
    }

    /// The opening: the black island grows into the launcher's frame, then dissolves onto it.
    enum Opening {
        /// The dissolve overlaps the spring's tail, so the launcher reads as soon as the black has arrived.
        static let handoff = 0.95
        static let dissolveDelay = IslandMotion.growing.time(reaching: handoff)
        static let dissolve = Theme.Duration.exit
        static let returnFade = Theme.Duration.enter
        /// The middle frame the gallery draws.
        static let middle: CGFloat = 0.5
    }
}
