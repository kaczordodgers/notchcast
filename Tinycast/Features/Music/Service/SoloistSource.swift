import Foundation

@MainActor
final class SoloistSource: NowPlayingSource {
    enum Failure: Error { case invalidPort, malformedFrame, connection, command(String), artwork }

    private(set) var authState: SoloistProtocol.AuthState?
    private(set) var failure: Failure?
    private(set) var isConnected = false
    private var state: NowPlaying?
    private var onChange: (@MainActor () -> Void)?
    private var port: Int?
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var coverTask: Task<Void, Never>?
    private var coverURL: URL?
    private var failedCoverURL: URL?
    private var covers: [URL: Data] = [:]
    private var attemptedCovers: Set<URL> = []
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    isolated deinit {
        worker?.cancel()
        sender?.cancel()
        coverTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    func connect(port: Int?) {
        guard port != self.port else { return }
        worker?.cancel()
        sender?.cancel()
        coverTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        self.port = port
        isConnected = false
        authState = nil
        state = nil
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
                    self?.state?.isPlaying = false
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

    private func receive(_ text: String) {
        do {
            failure = nil
            switch try SoloistProtocol.parse(text, now: Date()) {
            case .auth(let auth):
                authState = auth
                if auth.loggedIn { enqueue(SoloistProtocol.getState) }
            case .failure(let message): failure = .command(message)
            case .changed: enqueue(SoloistProtocol.getState)
            case .state(let track, let cover):
                state = track
                state?.artwork = cover.flatMap { covers[$0] }
                loadCover(cover)
            case .other: return
            }
        } catch { failure = .malformedFrame }
        onChange?()
    }

    private func loadCover(_ url: URL?) {
        guard url != coverURL || coverTask == nil else { return }
        coverURL = url
        coverTask?.cancel()
        coverTask = nil
        guard let url, url != failedCoverURL,
              ["https", "http"].contains(url.scheme), !attemptedCovers.contains(url) else { return }
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

    func send(_ command: PlayerCommand) {
        do {
            enqueue(try SoloistProtocol.encode(command, isPlaying: state?.isPlaying ?? false))
        } catch {
            failure = .command(String(describing: error))
            onChange?()
        }
    }
}
