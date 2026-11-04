import Darwin
import Foundation
import Synchronization

final class AgentSocketServer: Sendable {
    typealias Handler = @Sendable (AgentRequest) async -> AgentReply

    private struct Connections {
        var stopped = true
        var clients: [UUID: Connection] = [:]
        var persistent: Set<UUID> = []
    }

    private final class Connection: Sendable {
        struct State {
            var descriptor: Int32
            var cancelled = false
            var task: Task<Void, Never>?
        }

        let state: Mutex<State>
        let done = DispatchSemaphore(value: 0)

        init(_ descriptor: Int32) { state = Mutex(State(descriptor: descriptor)) }

        func cancel() {
            state.withLock {
                $0.cancelled = true
                $0.task?.cancel()
                if $0.descriptor >= 0 { shutdown($0.descriptor, SHUT_RDWR) }
            }
            done.signal()
        }

        func close() {
            state.withLock {
                $0.task?.cancel()
                $0.task = nil
                Darwin.close($0.descriptor)
                $0.descriptor = -1
            }
        }
    }

    private let socketURL: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "app.notchcast.agent-socket")
    private let connections = Mutex(Connections())
    @MainActor private var source: (any DispatchSourceRead)?
    @MainActor private var listenerEnded: DispatchSemaphore?
    private let readTimeout: Duration
    private let handlerTimeout: TimeInterval

    init(socketURL: URL, readTimeout: Duration = .seconds(5), handlerTimeout: TimeInterval = 30,
         handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handler = handler
        self.readTimeout = readTimeout
        self.handlerTimeout = handlerTimeout
    }

    @MainActor
    func start() throws {
        guard source == nil else { return }
        var address = try AgentSocketIO.address(socketURL.path)
        let lock = try lockDirectory()
        var descriptor: Int32 = -1
        var ownsSocket = false
        var identity = stat()
        do {
            var existing = stat()
            if lstat(socketURL.path, &existing) == 0 {
                guard existing.st_uid == geteuid(), existing.st_mode & S_IFMT == S_IFSOCK else {
                    throw AgentReply.Code.failed
                }
                guard unlink(socketURL.path) == 0 else { throw AgentReply.Code.failed }
            } else if errno != ENOENT {
                throw AgentReply.Code.failed
            }
            descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw AgentReply.Code.failed }
            try AgentSocketIO.configure(descriptor)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0 else { throw AgentReply.Code.failed }
            ownsSocket = true
            guard lstat(socketURL.path, &identity) == 0, identity.st_mode & S_IFMT == S_IFSOCK,
                identity.st_uid == geteuid()
            else { throw AgentReply.Code.failed }
            guard chmod(socketURL.path, 0o600) == 0, listen(descriptor, 8) == 0 else { throw AgentReply.Code.failed }
        } catch {
            if descriptor >= 0 { Darwin.close(descriptor) }
            if ownsSocket { Self.removeSocket(socketURL.path, device: identity.st_dev, inode: identity.st_ino) }
            Darwin.close(lock)
            throw error
        }
        connections.withLock { $0.stopped = false }
        let listener = descriptor
        let ended = DispatchSemaphore(value: 0)
        let path = socketURL.path
        let device = identity.st_dev
        let inode = identity.st_ino
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler { @Sendable [weak self] in self?.acceptClients(listener) }
        source.setCancelHandler { @Sendable in
            Darwin.close(listener)
            Self.removeSocket(path, device: device, inode: inode)
            Darwin.close(lock)
            ended.signal()
        }
        self.source = source
        listenerEnded = ended
        source.resume()
    }

    private static func removeSocket(_ path: String, device: dev_t, inode: ino_t) {
        var current = stat()
        guard lstat(path, &current) == 0, current.st_mode & S_IFMT == S_IFSOCK,
            current.st_dev == device, current.st_ino == inode
        else { return }
        unlink(path)
    }

    @MainActor
    func stop() {
        guard let source else { return }
        connections.withLock {
            $0.stopped = true
            for client in $0.clients.values { client.cancel() }
        }
        source.cancel()
        listenerEnded?.wait()
        listenerEnded = nil
        self.source = nil
    }

    private func lockDirectory() throws -> Int32 {
        let folder = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
            info.st_uid == geteuid(), chmod(folder.path, 0o700) == 0
        else { throw AgentReply.Code.failed }
        let descriptor = open(folder.appending(path: "lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw AgentReply.Code.failed }
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_uid == geteuid(), info.st_nlink == 1, fchmod(descriptor, 0o600) == 0,
            flock(descriptor, LOCK_EX | LOCK_NB) == 0
        else {
            Darwin.close(descriptor)
            throw AgentReply.Code.failed
        }
        return descriptor
    }

    private func acceptClients(_ listener: Int32) {
        for _ in 0..<8 {
            guard !connections.withLock({ $0.stopped }) else { return }
            let descriptor = accept(listener, nil, nil)
            guard descriptor >= 0 else { return }
            do {
                try AgentSocketIO.configure(descriptor)
            } catch {
                Darwin.close(descriptor)
                continue
            }
            guard AgentSocketIO.isSameUser(descriptor) else { Darwin.close(descriptor); continue }
            let connection = Connection(descriptor)
            let id = UUID()
            let accepted = connections.withLock {
                guard !$0.stopped, $0.clients.count - $0.persistent.count < 8 else { return false }
                $0.clients[id] = connection
                return true
            }
            guard accepted else { connection.close(); continue }
            Thread.detachNewThread { @Sendable [self] in serve(connection, id: id, descriptor: descriptor) }
        }
    }

    private func serve(_ connection: Connection, id: UUID, descriptor: Int32) {
        var session: String?
        defer {
            connection.close()
            connections.withLock {
                $0.clients[id] = nil
                $0.persistent.remove(id)
            }
            if let session {
                Task { [handler] in _ = await handler(.init(verb: .mcp, id: session, parameters: .null)) }
            }
        }
        var keepAlive = false
        repeat {
            let reply: AgentReply
            do {
                let line = try AgentSocketIO.readLine(descriptor, timeout: keepAlive ? .seconds(86400) : readTimeout)
                let request: AgentRequest
                do {
                    request = try JSONDecoder().decode(AgentRequest.self, from: line)
                } catch {
                    throw AgentReply.Code.badRequest
                }
                keepAlive = request.verb == .mcp && request.keepAlive
                if keepAlive {
                    let admitted = connections.withLock {
                        if $0.persistent.contains(id) { return true }
                        guard $0.persistent.count < 64 else { return false }
                        $0.persistent.insert(id)
                        return true
                    }
                    guard admitted else { throw AgentReply.Code.failed }
                    session = request.id
                }
                let answer = Mutex<AgentReply?>(nil)
                let done = connection.done
                let handler = handler
                connection.state.withLock { state in
                    guard !state.cancelled else { return }
                    state.task = Task {
                        let reply = await handler(request)
                        answer.withLock { $0 = reply }
                        done.signal()
                    }
                }
                guard !connection.state.withLock({ $0.cancelled }) else { return }
                try waitForReply(connection, descriptor: descriptor)
                reply = answer.withLock { $0 } ?? .init(code: .failed)
            } catch let code as AgentReply.Code {
                keepAlive = false
                reply = .init(code: code)
            } catch {
                keepAlive = false
                reply = .init(code: .failed)
            }
            connection.state.withLock { $0.task?.cancel() }
            do {
                try AgentSocketIO.write(AgentSocketIO.frame(reply), to: descriptor, timeout: .seconds(5))
            } catch { return }
        } while keepAlive
    }

    private func waitForReply(_ connection: Connection, descriptor: Int32) throws {
        let deadline = ContinuousClock.now + .seconds(handlerTimeout)
        while ContinuousClock.now < deadline {
            if connection.done.wait(timeout: .now() + 0.05) == .success {
                guard !connection.state.withLock({ $0.cancelled }) else { throw AgentReply.Code.failed }
                return
            }
            var byte: UInt8 = 0
            let received = recv(descriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            guard received < 0, errno == EAGAIN || errno == EINTR else { throw AgentReply.Code.failed }
        }
        throw AgentReply.Code.failed
    }
}
