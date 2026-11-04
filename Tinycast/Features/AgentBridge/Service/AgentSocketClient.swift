import Darwin
import Foundation

enum AgentSocketClient {
    static func send(_ request: AgentRequest, to socketURL: URL) -> AgentReply {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .init(code: .notRunning) }
        defer { Darwin.close(descriptor) }
        do {
            var address = try AgentSocketIO.address(socketURL.path)
            try AgentSocketIO.configure(descriptor)
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else {
                return .init(code: errno == ENOENT || errno == ECONNREFUSED ? .notRunning : .failed)
            }
            guard AgentSocketIO.isSameUser(descriptor) else { return .init(code: .failed) }
            try AgentSocketIO.write(AgentSocketIO.frame(request), to: descriptor, timeout: .seconds(5))
            let data = try AgentSocketIO.readLine(descriptor, timeout: .seconds(35))
            return try JSONDecoder().decode(AgentReply.self, from: data)
        } catch {
            return .init(code: .failed)
        }
    }

    static func socketURL(home: URL, bundleID: String) -> URL {
        home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "agent/socket", directoryHint: .notDirectory)
    }
}
