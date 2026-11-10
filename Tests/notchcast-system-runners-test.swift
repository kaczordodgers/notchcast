// notchcast-sources: Tinycast/Features/SystemTools/Model/*.swift Tinycast/Features/SystemTools/Service/*.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/*.swift Tinycast/Features/Tweaks/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemTools/UI/SystemToolsProcessRunner.swift
// notchcast-kit: platform
import Foundation

@main
struct SystemRunnerTests {
    static func main() throws {
        do {
            _ = try SystemToolsProcessRunner().run("/bin/sh", arguments: [])
            preconditionFailure("Shell execution must be rejected")
        } catch SystemToolsProcessRunner.Failure.invalidExecutable {}
        let domains = try SystemToolsProcessRunner().run("/usr/bin/defaults", arguments: ["domains"])
        precondition(domains.contains("com.apple"))
        do {
            _ = try SystemToolsProcessRunner().run("/usr/bin/defaults", arguments: ["read", "notchcast-no-such-domain"])
            preconditionFailure("A failing tool must throw")
        } catch SystemToolsProcessRunner.Failure.failed(let status) { precondition(status == 1) }
        let item = StartupItem(label: "example.agent", kind: .userAgent,
                               path: "/example/Library/LaunchAgents/example.plist",
                               program: nil, disabled: false, loaded: true)
        var calls: [[String]] = []
        try StartupItemService().apply(item, enabled: false, uid: 501, home: "/example") {
            calls.append($0)
        }
        precondition(calls == [["disable", "gui/501/example.agent"], ["bootout", "gui/501/example.agent"]])
        print("Runner shell rejection, real defaults runs and injected startup reversal passed")
    }
}
