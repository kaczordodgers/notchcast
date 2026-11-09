// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoStore*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoIsland*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoLinkCoordinator.swift
// notchcast-sources: Tinycast/Features/Todo/TodoModule.swift Tinycast/Features/Todo/TodoLinkWiring.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
// notchcast-sources: Tinycast/Features/MachLink/Service/MachLinkChannel.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkRequestBudget.swift
// notchcast-sources: Tinycast/Features/Notchcast/Root/RootContract.swift
import Foundation
import Network

func loopChild(_ index: Int) async -> String? {
    let process = Process()
    process.executableURL = URL(filePath: CommandLine.arguments[0])
    process.environment = ProcessInfo.processInfo.environment.merging(["NC_LOOP_CHILD": "1"]) { $1 }
    let log = FileManager.default.temporaryDirectory.appending(path: "nc-loop-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let handle = try! FileHandle(forWritingTo: log)
    process.standardOutput = handle
    process.standardError = handle
    let status: Int32 = await withCheckedContinuation { continuation in
        process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        try! process.run()
    }
    if status == 0 { return nil }
    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    return "child \(index) status \(status): " + text.split(separator: "\n").suffix(6).joined(separator: " | ")
}

@MainActor func loopOfTwenty(_ name: String, once: @MainActor () async throws -> Void) async throws {
    if ProcessInfo.processInfo.environment["NC_LOOP_CHILD"] != nil { try await once(); return }
    var failures: [String] = []
    for wave in 0..<4 {
        let results = await withTaskGroup(of: String?.self) { group in
            for index in 0..<5 { group.addTask { await loopChild(wave * 5 + index) } }
            var collected: [String] = []
            for await result in group { if let result { collected.append(result) } }
            return collected
        }
        failures += results
    }
    print("LOOP \(name): \(failures.count) failures of 20")
    for failure in failures.prefix(4) { print("LOOP \(failure)") }
    if !failures.isEmpty { exit(1) }
}

struct MachLinkPairing: Sendable {
    let id = UUID()
    let secret = Data([1])
    let discoveryHash = "fake"
}

extension MachLinkChannel {
    static func paired() -> MachLinkChannel {
        let channel = MachLinkChannel()
        channel.pairing = MachLinkPairing()
        channel.endpoint = .hostPort(host: "unused.invalid", port: 1)
        return channel
    }
}

@MainActor final class MachLinkManager {
    var routes: [String: @MainActor (MachLinkMessage) async throws -> MachLinkMessage] = [:]
    var peers: Set<NWBrowser.Result> = []
    var serviceName: String?
    static var fakeRequest: ((MachLinkMessage) async throws -> MachLinkMessage)?

    func register(_ method: String, _ route: @escaping @MainActor (MachLinkMessage) async throws -> MachLinkMessage) {
        routes[method] = route
    }

    static func request<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ value: Request, method: String, from endpoint: NWEndpoint,
        pairing: MachLinkPairing, timeout: Duration, as type: Response.Type
    ) async throws -> Response {
        guard let fakeRequest else { throw MachLinkMessage.Failure.disconnected }
        let request = try MachLinkMessage(method: method, value: value)
        let response = try await fakeRequest(request)
        guard response.id == request.id, response.method == request.method else {
            throw MachLinkMessage.Failure.invalidMessage
        }
        return try response.value(as: type)
    }
}

@MainActor final class FakeChannel {
    weak var peer: TodoLinkCoordinator?
    var dropResponse = false
    var calls = 0
    var active = 0
    var maximumActive = 0
    var held = false
    var cancellationSeen = false
    var entered: CheckedContinuation<Void, Never>?
    var reply: CheckedContinuation<Void, Never>?

    func request(_ packet: TodoLinkPacket) async throws -> TodoLinkPacket {
        let request = try MachLinkMessage(method: "todo-sync", value: packet)
        let response = try await send(request)
        return try response.value(as: TodoLinkPacket.self)
    }

    func send(_ message: MachLinkMessage) async throws -> MachLinkMessage {
        calls += 1
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        let request = try MachLinkMessage.decode(message.encoded())
        if held {
            entered?.resume()
            entered = nil
            await withCheckedContinuation { reply = $0 }
            cancellationSeen = Task.isCancelled
        } else { await Task.yield() }
        guard let peer else { throw MachLinkMessage.Failure.disconnected }
        let response = try peer.response(to: request)
        precondition(response.id == request.id && response.method == request.method)
        let decoded = try MachLinkMessage.decode(response.encoded())
        if dropResponse {
            dropResponse = false
            throw MachLinkMessage.Failure.disconnected
        }
        return decoded
    }
}

@main @MainActor
struct TodoLinkTests {
    static func main() async throws { try await loopOfTwenty("nc-Todo-link-test", once: once) }

    static func once() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await convergence(root)
        try await lifecycle(root)
        try await peerChecks()
        try await cancellation(root)
        try await paging(root)
        try await pairingChange(root)
        try await oversized(root)
        try await failures(root)
        try await outage(root)
        print("PASS: Todo Mac Link fake-channel suite")
    }

    static func idle(_ coordinator: TodoLinkCoordinator) async throws {
        for _ in 0..<2_000 {
            if !coordinator.isExchanging { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("exchange did not settle")
    }

    static func outage(_ root: URL) async throws {
        let suite = "test.todo-link.outage.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        for feature: NotchcastFeature in [.tasks, .machLink, .tasksSync] { preferences.set(feature, true) }
        let store = try await TodoStore.open(directory: root.appending(path: "outage"))
        var failures: [MachLinkMessage.Failure] = [.timedOut, .disconnected, .invalidMessage]
        MachLinkManager.fakeRequest = { _ in throw failures.removeFirst() }
        defer { MachLinkManager.fakeRequest = nil }
        let coordinator = TodoLinkCoordinator.live(channel: .paired(), preferences: preferences)
        var messages: [String] = []
        coordinator.showFailure = { messages.append($0) }
        coordinator.opened(store)
        coordinator.start()
        try await idle(coordinator)
        coordinator.requestExchange()
        try await idle(coordinator)
        coordinator.requestExchange()
        try await idle(coordinator)
        precondition(failures.isEmpty && messages.count == 1)
        coordinator.stop()
        try store.close()
        print("PASS: a timeout, then a disconnect, then a bad reply report one outage once")
    }

    static func oversized(_ root: URL) async throws {
        for size in [45_000, 90_000] {
            let local = try await TodoStore.open(directory: root.appending(path: "large-\(size)"))
            let remote = try await TodoStore.open(directory: root.appending(path: "large-peer-\(size)"))
            try local.perform(.addTask(.init(id: UUID().uuidString, title: "Large",
                                           description: String(repeating: "x", count: size))))
            try remote.perform(.addTask(.init(id: UUID().uuidString, title: "Large peer",
                                            description: String(repeating: "y", count: size))))
            let peer = TodoLinkCoordinator(exchange: { _ in throw MachLinkMessage.Failure.disconnected })
            peer.opened(remote)
            peer.start()
            let channel = FakeChannel()
            channel.peer = peer
            channel.dropResponse = true
            let sender = TodoLinkCoordinator(exchange: channel.request)
            sender.opened(local)
            sender.start()
            try await idle(sender)
            sender.requestExchange()
            try await idle(sender)
            precondition(local.state == remote.state && remote.replication.envelopes.count == 2)
            sender.stop()
            peer.stop()
            try local.close()
            try remote.close()
        }
        print("PASS: envelopes over 40 KB and 64 KB converge after dropped chunk response without duplicates")
    }

    static func failures(_ root: URL) async throws {
        let store = try await TodoStore.open(directory: root.appending(path: "failures"))
        var messages: [String] = []
        var fails = true
        let coordinator = TodoLinkCoordinator(exchange: { packet in
            if fails { throw MachLinkMessage.Failure.disconnected }
            return .init(clock: packet.clock, envelopes: [], hasMore: false)
        })
        coordinator.showFailure = { messages.append($0) }
        coordinator.opened(store)
        coordinator.start()
        try await idle(coordinator)
        coordinator.requestExchange()
        try await idle(coordinator)
        precondition(messages.count == 1)
        fails = false
        coordinator.requestExchange()
        try await idle(coordinator)
        fails = true
        coordinator.requestExchange()
        try await idle(coordinator)
        precondition(messages.count == 2)
        coordinator.stop()
        coordinator.start()
        try await idle(coordinator)
        precondition(messages.count == 3, "restarting sync shows a still-failing peer again")
        try store.perform(.addTask(.init(id: UUID().uuidString, title: "Original")))
        var clone = TodoReplication(replicaID: store.replication.replicaID)
        try clone.perform(.addTask(.init(id: UUID().uuidString, title: "Conflict")))
        let packet = TodoLinkPacket(clock: .init(), envelopes: clone.envelopes, hasMore: false)
        let before = store.state
        for _ in 0..<2 {
            do {
                _ = try coordinator.respond(packet)
                preconditionFailure("conflicting replica accepted")
            } catch TodoReplicationError.conflictingEnvelope {}
        }
        precondition(messages.count == 4 && messages.last!.contains("replica ID"))
        precondition(store.state == before)
        coordinator.stop()
        try store.close()
        print("PASS: failure messages deduplicate, success resets, replica conflicts stay atomic and visible")
    }

    static func convergence(_ root: URL) async throws {
        let firstURL = root.appending(path: "first")
        let secondURL = root.appending(path: "second")
        let first = try await TodoStore.open(directory: firstURL)
        let second = try await TodoStore.open(directory: secondURL)
        let channel = FakeChannel()
        let responder = TodoLinkCoordinator(exchange: { _ in throw MachLinkMessage.Failure.disconnected })
        responder.opened(second)
        responder.start()
        await Task.yield()
        channel.peer = responder
        let sender = TodoLinkCoordinator(debounceDelay: .milliseconds(10), exchange: channel.request)
        sender.opened(first)
        let task = TodoTask(id: UUID().uuidString, title: "Shared")
        try first.perform(.addTask(task))
        sender.start()
        try await idle(sender)
        precondition(first.state == second.state)
        var left = first.state.tasks[task.id]!
        var right = second.state.tasks[task.id]!
        left.title = "First title"
        left.priority = 4
        right.title = "Second title"
        right.description = "Peer description"
        try first.perform(.updateTask(left))
        try second.perform(.updateTask(right))
        let expected = try TodoReplication.merge(local: first.replication,
            remote: second.replication.envelopes, now: Date()).state
        sender.requestExchange()
        try await idle(sender)
        precondition(first.state == expected && second.state == expected)
        precondition(first.state.tasks[task.id]?.priority == 4)
        precondition(first.state.tasks[task.id]?.description == "Peer description")
        precondition(first.state.tasks[task.id]?.title ==
            (first.replication.replicaID < second.replication.replicaID ? right.title : left.title))
        print("PASS: two stores converge; conflicting fields use existing LWW; unrelated edits survive")

        let comment = TodoComment(id: UUID().uuidString, text: "Durable", createdAt: Date())
        try first.perform(.addComment(taskID: task.id, comment: comment))
        channel.dropResponse = true
        sender.requestExchange()
        try await idle(sender)
        precondition(second.state.tasks[task.id]?.comments == [comment])
        let count = second.replication.envelopes.count
        let bytes = try Data(contentsOf: secondURL.appending(path: "commands.jsonl"))
        sender.requestExchange()
        try await idle(sender)
        precondition(second.replication.envelopes.count == count)
        let retriedBytes = try Data(contentsOf: secondURL.appending(path: "commands.jsonl"))
        precondition(retriedBytes == bytes)
        precondition(first.state == second.state)
        print("PASS: dropped response retries without duplicate envelopes, comments or log appends")

        let before = channel.calls
        try first.undo()
        try first.perform(.addComment(taskID: task.id, comment: comment))
        try first.perform(.completeTask(id: task.id, at: Date()))
        try await Task.sleep(for: .milliseconds(40))
        try await idle(sender)
        precondition(first.state == second.state && channel.calls == before + 1)
        precondition(channel.maximumActive == 1)
        sender.stop()
        responder.stop()
        let state = first.state
        try first.close()
        try second.close()
        let restored = try await TodoStore.open(directory: firstURL)
        let restoredPeer = try await TodoStore.open(directory: secondURL)
        precondition(restored.state == state && restoredPeer.state == state)
        try restored.close()
        try restoredPeer.close()
        print("PASS: local commits and undo debounce; no concurrent exchanges; both logs survive reopen")
    }

    static func lifecycle(_ root: URL) async throws {
        let suite = "test.todo-link.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(!preferences.isOn(.tasksSync))
        precondition(NotchcastFeature.tasksSync.dependencies == [.tasks, .machLink])
        precondition(NotchcastFeature.tasksSync.settingsGroup == .tasks)
        let module = TodoModule(directory: root.appending(path: "module"), showFailure: { _ in
            preconditionFailure("module failed")
        })
        let channel = MachLinkChannel.paired()
        var calls = 0
        MachLinkManager.fakeRequest = { request in
            calls += 1
            let value = try request.value(as: TodoLinkPacket.self)
            return try MachLinkMessage(id: request.id, method: request.method,
                value: TodoLinkPacket(clock: value.clock, envelopes: [], hasMore: false))
        }
        defer { MachLinkManager.fakeRequest = nil }
        let sync = TodoLinkCoordinator.live(channel: channel, preferences: preferences)
        sync.connect(to: module)
        let controller = NotchcastModuleController([
            .init(requires: [.tasksSync, .tasks, .machLink], module: sync),
            .init(requires: [.tasks], module: module)
        ], preferences: preferences)
        controller.run()
        precondition(!sync.isRunning && calls == 0)
        preferences.set(.tasksSync, true)
        await Task.yield()
        precondition(!sync.isRunning && calls == 0)
        preferences.set(.tasks, true)
        preferences.set(.machLink, true)
        for _ in 0..<200 where module.store == nil { try await Task.sleep(for: .milliseconds(2)) }
        try await idle(sync)
        precondition(module.store != nil && sync.isRunning && calls == 1)
        preferences.set(.tasksSync, false)
        for _ in 0..<100 where sync.isRunning { await Task.yield() }
        precondition(!sync.isRunning && module.store != nil)
        preferences.set(.tasksSync, true)
        for _ in 0..<200 where calls == 1 { try await Task.sleep(for: .milliseconds(2)) }
        try await idle(sync)
        precondition(calls == 2)
        preferences.set(.machLink, false)
        for _ in 0..<100 where sync.isRunning { await Task.yield() }
        precondition(!sync.isRunning && module.store != nil)
        module.stop()
        print("PASS: default off, dependency switches, store-open trigger and live adapter over fake requests")
    }

    static func peerChecks() async throws {
        let suite = "test.todo-link.peer.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let channel = MachLinkChannel.paired()
        let coordinator = TodoLinkCoordinator.live(channel: channel, preferences: NotchcastPreferences(suiteName: suite))
        guard let route = channel.manager.routes["todo-sync"] else { preconditionFailure("todo-sync not registered") }
        let message = try MachLinkMessage(method: "todo-sync", value: true)
        defer { coordinator.stop() }
        do {
            _ = try await route(message)
            preconditionFailure("stopped coordinator accepted")
        } catch MachLinkMessage.Failure.disconnected {}
        print("PASS: registered todo-sync route refuses a peer that cannot sync")
    }

    static func cancellation(_ root: URL) async throws {
        let store = try await TodoStore.open(directory: root.appending(path: "cancel"))
        let channel = FakeChannel()
        channel.held = true
        let coordinator = TodoLinkCoordinator(exchange: channel.request)
        coordinator.opened(store)
        await withCheckedContinuation { continuation in
            channel.entered = continuation
            coordinator.start()
        }
        coordinator.closed()
        coordinator.stop()
        coordinator.opened(store)
        coordinator.start()
        precondition(channel.calls == 1)
        channel.held = false
        channel.reply?.resume()
        channel.reply = nil
        try await idle(coordinator)
        precondition(channel.cancellationSeen && store.state.tasks.isEmpty)
        precondition(channel.calls == 2 && channel.maximumActive == 1)
        coordinator.stop()
        try store.close()
        print("PASS: teardown cancels the in-flight request")

        let staleStore = try await TodoStore.open(directory: root.appending(path: "stale"))
        let remote = try await TodoStore.open(directory: root.appending(path: "stale-peer"))
        try remote.perform(.addTask(.init(id: UUID().uuidString, title: "Late reply")))
        var release: CheckedContinuation<Void, Never>?
        var entered: CheckedContinuation<Void, Never>?
        let stale = TodoLinkCoordinator(exchange: { _ in
            entered?.resume()
            entered = nil
            await withCheckedContinuation { release = $0 }
            return try TodoLinkPacket.make(from: remote.replication, after: TodoVectorClock())
        })
        stale.opened(staleStore)
        await withCheckedContinuation { continuation in entered = continuation; stale.start() }
        stale.stop()
        release?.resume()
        try await idle(stale)
        precondition(staleStore.state.tasks.isEmpty)
        try staleStore.close()
        try remote.close()
        print("PASS: a cancellation-insensitive late response cannot mutate the stopped store")
    }

    static func paging(_ root: URL) async throws {
        let local = try await TodoStore.open(directory: root.appending(path: "pages"))
        let remote = try await TodoStore.open(directory: root.appending(path: "pages-peer"))
        for index in 0..<12 {
            try local.perform(.addTask(.init(id: UUID().uuidString, title: "Local \(index)",
                                            description: String(repeating: "A", count: 4_000))))
            try remote.perform(.addTask(.init(id: UUID().uuidString, title: "Remote \(index)",
                                             description: String(repeating: "B", count: 4_000))))
        }
        let peer = TodoLinkCoordinator(exchange: { _ in throw MachLinkMessage.Failure.disconnected })
        peer.opened(remote)
        peer.start()
        let channel = FakeChannel()
        channel.peer = peer
        let sender = TodoLinkCoordinator(exchange: channel.request)
        sender.opened(local)
        sender.start()
        try await idle(sender)
        precondition(local.state == remote.state && local.state.tasks.count == 24 && channel.calls > 1)
        sender.stop()
        peer.stop()
        try local.close()
        try remote.close()
        print("PASS: bidirectional paging fits actual Mac Link frames and converges")
    }

    static func pairingChange(_ root: URL) async throws {
        let suite = "test.todo-link.pairing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        for feature: NotchcastFeature in [.tasks, .machLink, .tasksSync] { preferences.set(feature, true) }
        let store = try await TodoStore.open(directory: root.appending(path: "pairing"))
        var replication = TodoReplication(replicaID: "peer")
        try replication.perform(.addTask(.init(id: UUID().uuidString, title: "Old pairing")))
        let packet = try TodoLinkPacket.make(from: replication, after: TodoVectorClock())
        let channel = MachLinkChannel.paired()
        MachLinkManager.fakeRequest = { request in
            await Task.yield()
            channel.pairing = MachLinkPairing()
            return try MachLinkMessage(id: request.id, method: request.method, value: packet)
        }
        defer { MachLinkManager.fakeRequest = nil }
        let coordinator = TodoLinkCoordinator.live(channel: channel, preferences: preferences)
        coordinator.opened(store)
        coordinator.start()
        try await idle(coordinator)
        precondition(store.state.tasks.isEmpty)
        coordinator.stop()
        try store.close()
        print("PASS: a reply from a replaced pairing is discarded before persistence")
    }
}
