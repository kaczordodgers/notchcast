import Foundation

@main
enum NotchcastCLI {
    static func main() {
        do {
            let parsed = try AgentRequest.parse(Array(CommandLine.arguments.dropFirst()))
            guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
                throw AgentReply.Code.notRunning
            }
            let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard let bundleID = Bundle(url: app)?.bundleIdentifier else { throw AgentReply.Code.notRunning }
            let reply = AgentSocketClient.send(parsed.request, to: AgentSocketClient.socketURL(
                home: FileManager.default.homeDirectoryForCurrentUser, bundleID: bundleID))
            let encoder = JSONEncoder()
            encoder.outputFormatting = parsed.json ? [.sortedKeys] : [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(reply)
            FileHandle.standardOutput.write(data + Data([UInt8(ascii: "\n")]))
            exit(reply.code.exit)
        } catch {
            let code = (error as? AgentReply.Code) ?? .badRequest
            let text = "{\"code\":\"\(code.rawValue)\",\"result\":null}\n"
            FileHandle.standardOutput.write(Data(text.utf8))
            exit(code.exit)
        }
    }
}
