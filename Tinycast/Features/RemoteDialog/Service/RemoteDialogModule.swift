import Foundation

@MainActor
final class RemoteDialogModule: NotchcastModule {
    struct Dialog: Codable, Hashable, Sendable {
        let processID: Int
        let windowID: Int
    }

    struct Notice: Codable, Sendable {
        let occurrence: UUID
        let macName: String
    }

    private let windows: () -> Set<Dialog>
    private let macName: () -> String
    private let send: (Notice) async throws -> Void
    private let post: (String) -> Void
    private var seen: Set<Dialog> = []
    private var received: [UUID] = []
    private var task: Task<Void, Never>?
    private(set) var isRunning = false

    init(windows: @escaping () -> Set<Dialog>, macName: @escaping () -> String,
         send: @escaping (Notice) async throws -> Void, post: @escaping (String) -> Void) {
        self.windows = windows
        self.macName = macName
        self.send = send
        self.post = post
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
        seen.removeAll()
        received.removeAll()
    }

    func poll() async {
        guard isRunning, !Task.isCancelled else { return }
        let current = windows()
        let added = current.subtracting(seen)
        seen = current
        for _ in added {
            guard isRunning, !Task.isCancelled else { return }
            do {
                try await send(Notice(occurrence: UUID(), macName: macName()))
            } catch is CancellationError { return } catch { continue }
        }
    }

    func receive(_ notice: Notice) {
        guard isRunning, !received.contains(notice.occurrence),
              !notice.macName.isEmpty, notice.macName.count <= 255,
              notice.macName.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil else { return }
        received.append(notice.occurrence)
        if received.count > 256 { received.removeFirst() }
        post(String(localized: "\(notice.macName) is waiting on a system dialog"))
    }

    func response(to request: MachLinkMessage) throws -> MachLinkMessage {
        guard isRunning, request.method == "dialog-shown" else {
            throw MachLinkMessage.Failure.disconnected
        }
        receive(try request.value(as: Notice.self))
        return try MachLinkMessage(id: request.id, method: request.method, value: true)
    }
}
