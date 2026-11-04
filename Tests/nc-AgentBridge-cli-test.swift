import Foundation

@main
@MainActor
struct AgentCLITests {
    static func check(_ value: Bool, _ message: String = "check failed") { precondition(value, message) }

    static func main() throws {
        for verb in ["status", "list", "audit"] {
            let parsed = try AgentRequest.parse([verb, "--json"])
            check(parsed.json && parsed.request.verb.rawValue == verb && parsed.request.isValid)
        }
        let parsed = try AgentRequest.parse(["--json", "run", "fixture", "{\"level\":0.5}", "--dry-run"])
        check(parsed.json && parsed.request.dryRun && parsed.request.parameters == .object(["level": .number(0.5)]))
        check(try AgentRequest.parse(["get", "fixture.state"]).request.id == "fixture.state")
        for arguments in [[], ["unknown"], ["status", "extra"], ["get"], ["list", "--dry-run"],
                          ["run"], ["run", "fixture", "[]"], ["run", "fixture", "{"],
                          ["run", "fixture", "{}", "extra"], ["get", ""]] {
            do { _ = try AgentRequest.parse(arguments); preconditionFailure("bad arguments accepted") } catch {}
        }
        let minimal = try JSONDecoder().decode(AgentRequest.self, from: Data("{\"verb\":\"status\"}".utf8))
        check(minimal == .init(verb: .status))
        let null = try JSONDecoder().decode(AgentRequest.self, from: Data("{\"verb\":\"status\",\"parameters\":null}".utf8))
        check(!null.isValid)
        let reply = AgentReply(code: .declined, result: .object(["nested": .array([.null, .bool(false), .number(1)])]))
        check(try JSONDecoder().decode(AgentReply.self, from: JSONEncoder().encode(reply)) == reply)
        check([AgentReply.Code.ok, .failed, .badRequest, .notRunning, .declined].map(\.exit) == [0, 1, 2, 3, 5])
        let home = URL(filePath: "/fixture")
        check(AgentSocketClient.socketURL(home: home, bundleID: "app.notchcast")
              != AgentSocketClient.socketURL(home: home, bundleID: "app.notchcast.dev"))

        let folder = FileManager.default.temporaryDirectory.appending(path: "nc-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tool = folder.appending(path: "helper")
        try Data("fixture".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        let installer = AgentToolInstaller(source: tool, directory: folder.appending(path: "bin"))
        check(installer.state == .notInstalled)
        installer.install()
        check(installer.state == .installed)
        installer.install()
        check(installer.state == .installed)
        try FileManager.default.removeItem(at: installer.link)
        try Data("unrelated".utf8).write(to: installer.link)
        installer.install()
        check(installer.state == .failed)
        check(try String(contentsOf: installer.link, encoding: .utf8) == "unrelated")
        try FileManager.default.removeItem(at: installer.link)
        try FileManager.default.createSymbolicLink(at: installer.link, withDestinationURL: folder.appending(path: "other"))
        installer.install()
        check(installer.state == .failed)
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: installer.link.path)
        check(target == folder.appending(path: "other").path)
        print("PASS: CLI grammar, JSON wire defaults, exit codes, channel paths and non-destructive fixture installation")
    }
}
