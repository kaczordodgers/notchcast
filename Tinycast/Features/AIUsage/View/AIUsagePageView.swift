import SwiftUI

struct AIUsageAccount: Identifiable, Equatable {
    let id: String
    let name: String
    let plan: String?
    let readAt: Date?
    let isStale: Bool
    let windows: [AIUsageSnapshot.Window]
}

struct AIUsagePageView: View {
    enum Content: Equatable {
        case accounts([AIUsageAccount])
        case loading
        case gatewayDown
    }

    let content: Content
    var now = Date.now
    var isLive = false
    var onRetry: () -> Void = {}
    @Environment(\.metrics) private var metrics
    @Environment(\.islandHeaderHeight) private var headerHeight
    @State private var listHeight: CGFloat = 0

    var body: some View {
        switch content {
        case .accounts(let accounts) where accounts.isEmpty:
            Text("No AI accounts available.", tableName: "Notchcast")
                .foregroundStyle(NotchcastTheme.Colors.secondary)
                .padding(metrics.spacing.xxl)
        case .accounts(let accounts): list(accounts)
        case .loading:
            Text("Loading AI accounts…", tableName: "Notchcast")
                .foregroundStyle(NotchcastTheme.Colors.secondary)
                .padding(metrics.spacing.xxl)
        case .gatewayDown: gatewayDown
        }
    }

    private func list(_ accounts: [AIUsageAccount]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(accounts) { AIUsageAccountRow(account: $0, now: now, isLive: isLive) }
            }
            .padding(metrics.spacing.md)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .edgeDissolve()
        .thinScrollbar()
        .frame(height: listHeight == 0 ? nil : min(NotchcastTheme.maximumHeight - headerHeight, listHeight))
    }

    private var gatewayDown: some View {
        VStack(spacing: metrics.spacing.md) {
            SymbolImage(name: "gauge", size: metrics.size.dialogIcon)
                .accessibilityHidden(true)
            VStack(spacing: metrics.spacing.xxs) {
                Text("Magpie isn't running", tableName: "Notchcast")
                    .font(metrics.typography.rowTrailing)
                Text("Start Magpie to see how much of each AI account is left.", tableName: "Notchcast")
                    .font(NotchcastTheme.Typography.detail)
                    .foregroundStyle(NotchcastTheme.Colors.tertiary)
            }
            Button(action: onRetry) {
                Text("Retry")
            }
            .buttonStyle(.modalAction(.standard, fillsWidth: false))
        }
        .foregroundStyle(NotchcastTheme.Colors.secondary)
        .frame(maxWidth: .infinity)
        .padding(metrics.spacing.xxl)
    }
}

/// Name and plan on the left; each window a label and countdown over a bar and the share left.
private struct AIUsageAccountRow: View {
    let account: AIUsageAccount
    let now: Date
    let isLive: Bool
    @Environment(\.metrics) private var metrics

    var body: some View {
        let stale = account.isStale
        HStack(alignment: .top, spacing: NotchcastTheme.Usage.columnGap) {
            VStack(alignment: .leading, spacing: NotchcastTheme.Usage.lineGap) {
                Text(verbatim: account.name)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                HStack(spacing: metrics.spacing.xs) {
                    if let plan = account.plan { Text(verbatim: plan) }
                    if stale, let readAt = account.readAt {
                        Image(systemName: "clock")
                            .accessibilityHidden(true)
                        Text("as of \(readAt, format: .dateTime.hour().minute())", tableName: "Notchcast")
                    }
                }
                .font(NotchcastTheme.Typography.detail)
                .foregroundStyle(NotchcastTheme.Colors.secondary)
                .lineLimit(1)
            }
            .frame(width: NotchcastTheme.Usage.nameColumn, alignment: .leading)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: NotchcastTheme.Usage.windowColumn),
                                        spacing: NotchcastTheme.Usage.columnGap)],
                      alignment: .leading, spacing: metrics.spacing.sm) {
                ForEach(account.windows, id: \.id) { window in
                    AIUsageWindowCell(window: window, readAt: account.readAt, now: now, isLive: isLive)
                        .opacity(stale ? NotchcastTheme.Usage.staleOpacity : 1)
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

private struct AIUsageWindowCell: View {
    let window: AIUsageSnapshot.Window
    let readAt: Date?
    let now: Date
    let isLive: Bool
    @Environment(\.metrics) private var metrics
    @State private var resetNow: Date?

    private var left: Int { window.percentLeft(at: resetNow ?? now, readAt: readAt) }

    /// Low and empty windows take a hue and a mark, so the warning never rests on colour alone.
    private var tone: (color: Color, symbol: String)? {
        if left == 0 { return (NotchcastTheme.Colors.error, "xmark.circle.fill") }
        if left < NotchcastTheme.Usage.lowLeft { return (NotchcastTheme.Colors.warning, "exclamationmark.triangle.fill") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchcastTheme.Usage.lineGap) {
            HStack(spacing: metrics.spacing.xs) {
                Text(verbatim: window.label)
                    .foregroundStyle(NotchcastTheme.Colors.secondary)
                Spacer(minLength: metrics.spacing.xs)
                if isLive, let reset = window.resetsAt, reset > Date.now {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        countdown(at: context.date)
                    }
                } else {
                    countdown(at: resetNow ?? now)
                }
            }
            .font(NotchcastTheme.Typography.detail)
            .lineLimit(1)
            HStack(spacing: metrics.spacing.md) {
                AIUsageBar(left: left, tint: tone?.color ?? NotchcastTheme.Colors.secondary)
                HStack(spacing: metrics.spacing.xxs) {
                    if let tone {
                        Image(systemName: tone.symbol)
                            .accessibilityHidden(true)
                    }
                    Text("\(left)% left")
                        .monospacedDigit()
                }
                .font(NotchcastTheme.Typography.value)
                .foregroundStyle(tone?.color ?? NotchcastTheme.Colors.primary)
                .lineLimit(1)
                .frame(minWidth: NotchcastTheme.Usage.percentColumn, alignment: .trailing)
            }
        }
        .task(id: isLive ? window.resetsAt : nil) {
            resetNow = nil
            guard isLive, let reset = window.resetsAt else { return }
            let delay = reset.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            resetNow = .now
        }
    }

    @ViewBuilder private func countdown(at date: Date) -> some View {
        if let seconds = window.secondsUntilReset(at: date) {
            let countdown = AIUsageCountdown.text(seconds)
            Text("resets in \(countdown)", tableName: "Notchcast")
                .monospacedDigit()
                .foregroundStyle(NotchcastTheme.Colors.tertiary)
        }
    }
}

/// The share left, full when nothing is used: the bar shrinks as the window runs down.
private struct AIUsageBar: View {
    let left: Int
    let tint: Color

    var body: some View {
        Capsule()
            .fill(NotchcastTheme.Colors.control)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(left) / 100)
                }
            }
            .frame(height: NotchcastTheme.Usage.bar)
            .accessibilityHidden(true)
    }
}

/// "2h 14m", "3d 4h", "41m": the two largest units, abbreviated in the user's language.
@MainActor private enum AIUsageCountdown {
    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    static func text(_ seconds: TimeInterval) -> String {
        formatter.allowedUnits = seconds < 60 ? [.second] : [.day, .hour, .minute]
        return formatter.string(from: seconds) ?? ""
    }
}
