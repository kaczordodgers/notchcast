import Darwin
import Foundation

enum AgentSocketClient {
    final class Session {
        private var descriptor: Int32 = -1
        private var initialization: AgentRequest?

        deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

        func send(_ request: AgentRequest, to socketURL: URL) -> AgentReply {
            do {
                if descriptor < 0 {
                    descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
                    guard descriptor >= 0 else { return .init(code: .notRunning) }
                    try AgentSocketIO.configure(descriptor)
                    var address = try AgentSocketIO.address(socketURL.path)
                    let connected = withUnsafePointer(to: &address) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                        }
                    }
                    guard connected == 0, AgentSocketIO.isSameUser(descriptor) else {
                        Darwin.close(descriptor)
                        descriptor = -1
                        return .init(code: .notRunning)
                    }
                    if let initialization {
                        try AgentSocketIO.write(AgentSocketIO.frame(initialization), to: descriptor, timeout: .seconds(5))
                        let data = try AgentSocketIO.readLine(descriptor, timeout: .seconds(35))
                        guard try JSONDecoder().decode(AgentReply.self, from: data).code == .ok else {
                            throw AgentReply.Code.failed
                        }
                    }
                }
                var request = request
                request.keepAlive = true
                try AgentSocketIO.write(AgentSocketIO.frame(request), to: descriptor, timeout: .seconds(5))
                let data = try AgentSocketIO.readLine(descriptor, timeout: .seconds(35))
                let reply = try JSONDecoder().decode(AgentReply.self, from: data)
                if reply.code == .failed { throw AgentReply.Code.failed }
                if reply.code == .ok, case .string(let line) = request.parameters,
                   case .object(let fields) = try? JSONDecoder().decode(AgentJSON.self, from: Data(line.utf8)),
                   fields["method"] == .string("initialize") {
                    initialization = request
                }
                return reply
            } catch {
                if descriptor >= 0 { Darwin.close(descriptor) }
                descriptor = -1
                return .init(code: .failed)
            }
        }
    }

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
