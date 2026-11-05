import SwiftUI

/// Home's row parts, drawn from the closed island's own pieces so the two never drift.
struct IslandActivityGlyph: View {
    let activity: IslandActivity

    var body: some View {
        IslandActivityLine(activity: activity, part: .glyph)
    }
}

/// A row's value in the meeting countdown's chip; nothing without one, as the row's title names it.
struct IslandActivityValue: View {
    let activity: IslandActivity

    var body: some View {
        if let value = activity.value {
            IslandValueView(value: value, font: Theme.Typography.rowTrailing.weight(.medium))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(NotchcastTheme.Colors.control,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous))
        }
    }
}

typealias IslandStatusView = IslandMessageLine
