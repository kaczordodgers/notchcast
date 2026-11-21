import SwiftUI

struct NotchcastCommandRow<Title: View, Trailing: View, Controls: View>: View {
    @ViewBuilder let title: Title
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let controls: Controls

    var body: some View {
        NotchcastCommandRowLayout(horizontalSpacing: Theme.Spacing.lg, verticalSpacing: Theme.Spacing.md) {
            title.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.Spacing.lg) { controls }
            HStack(spacing: Theme.Spacing.lg) { trailing }
                .fixedSize()
        }
    }
}

struct NotchcastLauncherCheckboxLabel: View {
    let title: Text

    var body: some View {
        ViewThatFits(in: .horizontal) {
            title.fixedSize()
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

struct NotchcastCommandRowLayout: Layout {
    static let titleMinimum: CGFloat = 120
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    private struct Row {
        let stacked: Bool
        let title: ProposedViewSize
        let controls: ProposedViewSize
        let headerHeight: CGFloat
        let controlsHeight: CGFloat

        let height: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidth = subviews[0].sizeThatFits(.unspecified).width + horizontalSpacing
            + subviews[1].sizeThatFits(.unspecified).width + trailingWidth(subviews)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        return CGSize(width: width, height: row(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let row = row(width: bounds.width, subviews: subviews)
        let headerCenter = bounds.minY + (row.stacked ? row.headerHeight : row.height) / 2
        subviews[0].place(at: CGPoint(x: bounds.minX, y: headerCenter), anchor: .leading, proposal: row.title)
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: headerCenter), anchor: .trailing, proposal: .unspecified)
        let controlsCenter = row.stacked ? bounds.maxY - row.controlsHeight / 2 : headerCenter
        let controlsEnd = row.stacked ? bounds.maxX : bounds.maxX - trailingWidth(subviews)
        subviews[1].place(at: CGPoint(x: controlsEnd, y: controlsCenter), anchor: .trailing, proposal: row.controls)
    }

    private func row(width: CGFloat, subviews: Subviews) -> Row {
        let headerWidth = width - trailingWidth(subviews)
        let controlsWidth = subviews[1].sizeThatFits(.unspecified).width
        let inlineTitleWidth = headerWidth - controlsWidth - horizontalSpacing
        let stacked = inlineTitleWidth < subviews[0].sizeThatFits(.zero).width
        let title = ProposedViewSize(width: max(0, stacked ? headerWidth : inlineTitleWidth), height: nil)
        let controls = ProposedViewSize(width: min(width, controlsWidth), height: nil)
        let headerHeight = max(subviews[0].sizeThatFits(title).height, subviews[2].sizeThatFits(.unspecified).height)
        let controlsHeight = subviews[1].sizeThatFits(controls).height
        let height = stacked ? headerHeight + verticalSpacing + controlsHeight : max(headerHeight, controlsHeight)
        return Row(stacked: stacked, title: title, controls: controls,
                   headerHeight: headerHeight, controlsHeight: controlsHeight, height: height)
    }

    private func trailingWidth(_ subviews: Subviews) -> CGFloat {
        let width = subviews[2].sizeThatFits(.unspecified).width
        return width > 0 ? width + horizontalSpacing : 0
    }
}
