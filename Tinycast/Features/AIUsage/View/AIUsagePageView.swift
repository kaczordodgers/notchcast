import SwiftUI

/// One AI account as the usage page shows it: Magpie's alias or name, the plan, and each window it limits.
struct AIUsageAccount: Identifiable, Equatable {
    let id: String
    let name: String
    let plan: String?
    /// When Magpie read the numbers; `isCached` marks an answer it gave from cache (`asOf`).
    let readAt: Date
    var isCached = false
    let windows: [AIUsageSnapshot.Window]

    func isStale(at now: Date) -> Bool {
        isCached || now.timeIntervalSince(readAt) > NotchcastTheme.Usage.staleAfter
    }
}

/// The island's AI usage page: how much of each account is left, one row an account, in the order Magpie returns.
struct AIUsagePageView: View {
    enum Content: Equatable {
        case accounts([AIUsageAccount])
        case gatewayDown
    }

    let content: Content
    var now = Date.now
    var onRetry: () -> Void = {}
    @Environment(\.metrics) private var metrics
    @Environment(\.islandHeaderHeight) private var headerHeight
    @State private var listHeight: CGFloat = 0

    var body: some View {
        switch content {
        case .accounts(let accounts): list(accounts)
        case .gatewayDown: gatewayDown
        }
    }

    private func list(_ accounts: [AIUsageAccount]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(accounts) { AIUsageAccountRow(account: $0, now: now) }
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
                Text("Retry", tableName: "Notchcast")
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
    @Environment(\.metrics) private var metrics

    var body: some View {
        let stale = account.isStale(at: now)
        HStack(alignment: .top, spacing: NotchcastTheme.Usage.columnGap) {
            VStack(alignment: .leading, spacing: NotchcastTheme.Usage.lineGap) {
                Text(verbatim: account.name)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                HStack(spacing: metrics.spacing.xs) {
                    if let plan = account.plan { Text(verbatim: plan) }
                    if stale {
                        Image(systemName: "clock")
                            .accessibilityHidden(true)
                        Text("as of \(account.readAt, format: .dateTime.hour().minute())", tableName: "Notchcast")
                    }
                }
                .font(NotchcastTheme.Typography.detail)
                .foregroundStyle(NotchcastTheme.Colors.secondary)
                .lineLimit(1)
            }
            .frame(width: NotchcastTheme.Usage.nameColumn, alignment: .leading)
            ForEach(account.windows, id: \.id) { window in
                AIUsageWindowCell(window: window, now: now)
                    .frame(width: NotchcastTheme.Usage.windowColumn)
                    .opacity(stale ? NotchcastTheme.Usage.staleOpacity : 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

private struct AIUsageWindowCell: View {
    let window: AIUsageSnapshot.Window
    let now: Date
    @Environment(\.metrics) private var metrics

    private var left: Int { window.percentLeft }

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
                if let countdown = window.secondsUntilReset(at: now).map(AIUsageCountdown.text) {
                    Text("resets in \(countdown)", tableName: "Notchcast")
                        .monospacedDigit()
                        .foregroundStyle(NotchcastTheme.Colors.tertiary)
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
                    Text("\(left)% left", tableName: "Notchcast")
                        .monospacedDigit()
                }
                .font(NotchcastTheme.Typography.value)
                .foregroundStyle(tone?.color ?? NotchcastTheme.Colors.primary)
                .lineLimit(1)
                .frame(minWidth: NotchcastTheme.Usage.percentColumn, alignment: .trailing)
            }
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
private enum AIUsageCountdown {
    static func text(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds < 60 ? [.second] : [.day, .hour, .minute]
        return formatter.string(from: seconds) ?? ""
    }
}

#if DEBUG
extension AIUsageAccount {
    /// Eight accounts in Magpie's shape with every state on show: low, empty, cached, and windows with no reset.
    static func samples(now: Date) -> [AIUsageAccount] {
        func window(_ id: String, _ label: String, used: Double, resetsIn minutes: Double?) -> AIUsageSnapshot.Window {
            AIUsageSnapshot.Window(id: id, label: label, used: used, limit: 100,
                                   resetsAt: minutes.map { now.addingTimeInterval($0 * 60) }, durationMinutes: nil)
        }
        func claude(_ id: String, _ name: String, plan: String, _ used: (Double, Double, Double),
                    readAt: Date? = nil, cached: Bool = false) -> AIUsageAccount {
            AIUsageAccount(id: id, name: name, plan: plan, readAt: readAt ?? now, isCached: cached, windows: [
                window("five-hour", "5 hours", used: used.0, resetsIn: 134),
                window("seven-day", "7 days", used: used.1, resetsIn: 4_560),
                window("seven-day-fable", "7 days · Fable", used: used.2, resetsIn: 4_560),
            ])
        }
        return [
            claude("ultra", "Claude Ultra", plan: "Max", (43, 88, 5)),
            claude("team-1", "Claude Team #1", plan: "Team", (12, 34, 20)),
            claude("team-2", "Claude Team #2", plan: "Team", (100, 71, 40)),
            claude("team-3", "Claude Team #3", plan: "Team", (25, 50, 10),
                   readAt: now.addingTimeInterval(-40 * 60), cached: true),
            claude("team-4", "Claude Team #4", plan: "Team", (0, 9, 0)),
            claude("team-5", "Claude Team #5", plan: "Team", (66, 58, 31)),
            AIUsageAccount(id: "grok", name: "Grok", plan: "SuperGrok", readAt: now, windows: [
                window("seven-day", "7 days", used: 30, resetsIn: nil),
            ]),
            AIUsageAccount(id: "codex", name: "Codex", plan: "Pro", readAt: now, windows: [
                window("seven-day", "7 days", used: 62, resetsIn: 8_820),
                window("images", "Image generation", used: 83, resetsIn: nil),
            ]),
        ]
    }
}
#endif
