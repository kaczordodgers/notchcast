// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/AgentActionIndex.swift
// notchcast-sources: Tinycast/Features/AgentBridge/UI/AgentBridgeModule.swift
// notchcast-sources: Tinycast/Features/AgentBridge/UI/AgentConfirmationPresenter.swift
// notchcast-sources: Tinycast/Features/AgentConfirm/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentConfirm/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Service/*.swift
import Foundation

@MainActor protocol NotchcastModule { func start(); func stop() }
enum AppPaths { static func applicationSupport() -> URL { URL(filePath: "/unused") } }
enum NotchcastFeature: String, CaseIterable { case test }
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}
struct DialogAction {
    enum Role { case standard, cancel }
    let title: String
    var role = Role.standard
}
@MainActor final class AppCore {
    var allow = false
    var selection = 2
    var questions = 0
    func confirm(title: String, message: String?, symbol: String?, confirmTitle: String) async -> Bool {
        questions += 1
        return allow
    }
    func choose(title: String, message: String?, symbol: String?, options: [DialogAction],
                defaultIndex: Int) async -> Int {
        questions += 1
        return selection
    }
}
@MainActor enum AgentBuiltInActions {
    static var runs = 0
    static func register(in index: AgentActionIndex, core: AppCore) throws {
        for danger in [AgentAction.Danger.consent, .dangerous] {
            try index.register(.init(action: .init(id: danger.rawValue, title: danger.rawValue, danger: danger),
                                     run: { _ in runs += 1; return .null }))
        }
    }
}
@main @MainActor struct ConfirmationTests {
    static func main() async throws {
        let identifier = "test.confirm." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            UserDefaults().removePersistentDomain(forName: identifier + ".notchcast.agent-consent")
            try? FileManager.default.removeItem(at: directory)
        }
        let grants = try AgentGrantStore(bundleIdentifier: identifier)
        let audit = AgentAuditStore(directory: directory)
        let core = AppCore()
        let module = AgentBridgeModule()
        module.configure(core, grantStore: grants, auditStore: audit)
        module.start()
        let dangerous = AgentRequest(verb: .run, id: "dangerous")
        let denied = await module.index.handle(dangerous)
        precondition(denied.code == .declined && core.questions == 1 && AgentBuiltInActions.runs == 0)
        core.allow = true
        let allowed = await module.index.handle(dangerous)
        precondition(allowed.code == .ok && core.questions == 2 && grants.grants.isEmpty)
        _ = await module.index.handle(dangerous)
        precondition(core.questions == 3 && grants.grants.isEmpty)
        core.selection = 1
        let consent = AgentRequest(verb: .run, id: "consent")
        let remembered = await module.index.handle(consent)
        precondition(remembered.code == .ok && grants.grants.count == 1 && core.questions == 4)
        let next = await module.index.handle(consent)
        precondition(next.code == .ok && core.questions == 4 && AgentBuiltInActions.runs == 4)
        let entries = try await audit.entries()
        precondition(entries.map(\.verdict) == [.declined, .ran, .ran, .ran, .ran])
        try grants.revoke(agentID: "local-cli")
        core.selection = 2
        let revoked = await module.index.handle(consent)
        precondition(revoked.code == .declined && core.questions == 5)
        print("PASS: confirmation, denial audit, one-time danger, remembered consent and revocation")
    }
}
