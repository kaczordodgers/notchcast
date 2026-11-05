import SwiftUI

/// Home's row parts, drawn from the closed island's own pieces so the two never drift.
struct IslandActivityGlyph: View {
    let activity: IslandActivity

    var body: some View {
        IslandActivityLine(activity: activity, part: .glyph)
    }
}

struct IslandActivityValue: View {
    let activity: IslandActivity
    var multiple = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let value = activity.value {
                IslandValueView(value: value)
            } else {
                IslandWord(text: activity.title)
            }
            if multiple {
                Circle().fill(NotchcastTheme.Colors.tertiary)
                    .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
            }
        }
    }
}

typealias IslandStatusView = IslandMessageLine
