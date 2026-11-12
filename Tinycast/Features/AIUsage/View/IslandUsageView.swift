import SwiftUI

struct IslandUsageView: View {
    let module: AIUsageModule
    @Environment(IslandPagesCoordinator.self) private var pages

    private var content: AIUsagePageView.Content {
        if module.isLoading && module.refreshedAt == nil { return .loading }
        if module.gatewayDown { return .gatewayDown }
        if module.refreshedAt == nil { return .loading }
        return .accounts(module.snapshots.map(AIUsageAccount.init))
    }

    var body: some View {
        AIUsagePageView(content: content, isLive: pages.activePage == .usage, onRetry: { pages.refresh(.usage) })
            .onChange(of: NotchcastPreferences.shared.aiUsageGateway) {
                if pages.activePage == .usage { pages.refresh(.usage) }
            }
    }
}

extension AIUsageAccount {
    init(snapshot: AIUsageSnapshot) {
        id = snapshot.accountID
        name = snapshot.accountName
        plan = snapshot.plan
        readAt = snapshot.checkedAt
        isStale = snapshot.status == .stale
        windows = snapshot.windows
    }
}
