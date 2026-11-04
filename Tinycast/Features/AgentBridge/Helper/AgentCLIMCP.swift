import Foundation

enum AgentCLIMCP {
    static func run(bundleID: String) {
        do {
            let socket = AgentSocketClient.socketURL(
                home: FileManager.default.homeDirectoryForCurrentUser, bundleID: bundleID)
            let session = AgentSocketClient.Session()
            try AgentMCPStdio.run(input: .standardInput, output: .standardOutput) {
                session.send($0, to: socket)
            }
        } catch {
            FileHandle.standardError.write(Data("MCP stdio failed\n".utf8))
            exit(AgentReply.Code.failed.exit)
        }
    }
}
