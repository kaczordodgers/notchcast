// notchcast-sources: Tinycast/Features/LinkQuickFixes/Service/LinkQuickFixModule.swift
// notchcast-sources: Tinycast/Features/LinkQuickFixes/Model/LinkQuickFixEngine.swift
import Foundation

@MainActor
protocol NotchcastModule {
    func start()
    func stop()
}

@main @MainActor
struct LinkModuleTests {
    static func main() {
        let module = LinkQuickFixModule()
        let configuration = LinkQuickFixEngine.Configuration()
        precondition(module.actions(for: .cableDown, configuration: configuration).isEmpty)
        module.start()
        module.start()
        precondition(module.actions(for: .cableDown, configuration: configuration) == [.openNetworkSettings])
        module.stop()
        module.stop()
        precondition(module.actions(for: .cableDown, configuration: configuration).isEmpty)
        module.start()
        precondition(module.actions(for: .linkExpiring, configuration: configuration) == [.relinkInConnections])
        module.stop()
        print("PASS: link module gates actions across start, stop and restart")
    }
}
