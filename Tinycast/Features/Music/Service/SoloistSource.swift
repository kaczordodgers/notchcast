import Foundation
import Observation

@MainActor
@Observable
final class SoloistSource: NowPlayingSource {
    enum Failure: Error { case invalidPort, malformedFrame, connection, command(String), artwork }

    private(set) var authState: SoloistProtocol.AuthState?
    private(set) var failure: Failure?
    private(set) var isConnected = false
    private(set) var queue: [MusicQueueItem]?
    private var state: NowPlaying?
    private var onChange: (@MainActor () -> Void)?
    private var port: Int?
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refresh = SoloistRefreshState()
    private var coverTask: Task<Void, Never>?
    private var coverURL: URL?
    private var failedCoverURL: URL?
    private var covers: [URL: Data] = [:]
    private var attemptedCovers: Set<URL> = []
    private let session: URLSession

    init() {
        let configuration = NotchcastIdentity.sessionConfiguration()
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    isolated deinit {
        worker?.cancel()
        sender?.cancel()
        refreshTask?.cancel()
        coverTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    func connect(port: Int?) {
        guard port != self.port else { return }
        worker?.cancel()
        sender?.cancel()
        refreshTask?.cancel()
        refresh = SoloistRefreshState()
        coverTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        self.port = port
        isConnected = false
        authState = nil
        state = nil
        queue = nil
        coverURL = nil
        failure = nil
        onChange?()
        guard let port else { return }
        guard (1...65535).contains(port) else { failure = .invalidPort; return }
        worker = Task { [weak self] in
            var delay = 1
            while !Task.isCancelled {
                guard let socket = self?.open(port: port) else { return }
                do {
                    try await socket.send(.string(SoloistProtocol.getAuthState))
                    try await socket.send(.string(SoloistProtocol.getState))
                    try await socket.send(.string(SoloistProtocol.getQueue))
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        guard let owner = self, owner.socket === socket, !Task.isCancelled else { return }
                        delay = 1
                        owner.isConnected = true
                        switch message {
                        case .string(let text): owner.receive(text)
                        case .data(let data):
                            if let text = String(data: data, encoding: .utf8) { owner.receive(text) }
                        @unknown default: break
                        }
                    }
                } catch {
                    guard !Task.isCancelled, self?.socket === socket else { return }
                    self?.isConnected = false
                    self?.refreshTask?.cancel()
                    self?.refresh = SoloistRefreshState()
                    self?.authState = nil
                    self?.state = nil
                    self?.queue = nil
                    self?.failure = .connection
                    self?.onChange?()
                }
                socket.cancel(with: .goingAway, reason: nil)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                delay = min(delay * 2, 60)
            }
        }
    }

    private func open(port: Int) -> URLSessionWebSocketTask {
        let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)")!)
        socket.maximumMessageSize = 1_048_576
        self.socket = socket
        socket.resume()
        return socket
    }

    func receive(_ text: String) {
        isConnected = true
        do {
            failure = nil
            switch try SoloistProtocol.parse(text, now: Date()) {
            case .auth(let auth):
                let paired = auth.loggedIn && authState?.loggedIn == false
                authState = auth
                if !auth.loggedIn { queue = nil }
                if paired { requestRefresh(queue: true) }
            case .failure(let message): failure = .command(message)
            case .changed(let queue): requestRefresh(queue: queue)
            case .options(let shuffle, let repeatMode):
                if let shuffle { state?.shuffle = shuffle }
                if let repeatMode { state?.repeatMode = repeatMode }
                requestRefresh(queue: true)
            case .queue(let items):
                queue = items
            case .state(let track, let cover):
                state = track
                state?.artwork = cover.flatMap { covers[$0] }
                loadCover(cover)
            case .other: return
            }
        } catch { failure = .malformedFrame }
        onChange?()
    }

    private func requestRefresh(queue: Bool) {
        refresh.event(queue: queue, now: ProcessInfo.processInfo.systemUptime).forEach(enqueue)
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        guard let deadline = refresh.deadline, let socket else { return }
        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, deadline - ProcessInfo.processInfo.systemUptime)))
            } catch { return }
            guard let self, !Task.isCancelled, self.socket === socket else { return }
            self.refresh.flush(now: ProcessInfo.processInfo.systemUptime).forEach(self.enqueue)
            self.scheduleRefresh()
        }
    }

    private func loadCover(_ url: URL?) {
        guard url != coverURL || coverTask == nil else { return }
        coverURL = url
        coverTask?.cancel()
        coverTask = nil
        guard let url, url != failedCoverURL,
              WebRules.isWebScheme(url.scheme), !attemptedCovers.contains(url) else { return }
        let session = session
        coverTask = Task { [weak self] in
            do {
                let data = try await Self.download(url, session: session)
                guard !Task.isCancelled, let self, self.coverURL == url else { return }
                self.coverTask = nil
                if self.covers.values.reduce(0, { $0 + $1.count }) + data.count > 10_485_760 {
                    self.covers.removeAll()
                    self.attemptedCovers.removeAll()
                }
                self.attemptedCovers.insert(url)
                self.covers[url] = data
                self.state?.artwork = data
                self.onChange?()
            } catch {
                guard !Task.isCancelled, let self, self.coverURL == url else { return }
                self.coverTask = nil
                self.failure = .artwork
                self.failedCoverURL = url
                self.onChange?()
            }
        }
    }

    @concurrent
    private static func download(_ url: URL, session: URLSession) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              response.expectedContentLength <= 5_242_880 else { throw Failure.artwork }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 5_242_880 else { throw Failure.artwork }
            data.append(byte)
        }
        return data
    }

    private func enqueue(_ text: String) {
        guard let socket else { return }
        let previous = sender
        sender = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, self?.socket === socket else { return }
            do { try await socket.send(.string(text)) } catch {
                guard !Task.isCancelled, self?.socket === socket else { return }
                self?.failure = .command(String(describing: error))
                self?.onChange?()
            }
        }
    }

    func watch(_ onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }
    func unwatch() { onChange = nil }
    func read() async throws -> NowPlaying? { state }

    func addToQueue(uri: String) {
        do { enqueue(try SoloistProtocol.addToQueue(uri: uri)) } catch {
            failure = .command(String(describing: error))
            onChange?()
        }
    }

    func send(_ command: PlayerCommand) {
        do {
            enqueue(try SoloistProtocol.encode(command, isPlaying: state?.isPlaying ?? false))
        } catch {
            failure = .command(String(describing: error))
            onChange?()
        }
    }
}
