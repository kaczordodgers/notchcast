import SwiftUI

struct IslandUsageView: View {
    let module: AIUsageModule
    @Environment(IslandPagesCoordinator.self) private var pages

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            AIUsagePageView(
                content: module.gatewayDown ? .gatewayDown : .accounts(module.snapshots.map(AIUsageAccount.init)),
                now: context.date, onRetry: { pages.refresh(.usage) })
        }
        .onChange(of: NotchcastPreferences.shared.aiUsageGateway) { pages.refresh(.usage) }
    }
}

extension AIUsageAccount {
    init(snapshot: AIUsageSnapshot) {
        id = snapshot.accountID
        name = snapshot.accountName
        plan = snapshot.plan
        readAt = snapshot.checkedAt ?? .distantPast
        isCached = snapshot.status == .stale || snapshot.asOf != nil
        windows = snapshot.windows
    }
}
