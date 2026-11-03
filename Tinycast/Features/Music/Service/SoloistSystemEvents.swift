import AppKit
import Foundation

@MainActor
enum SoloistSystemEvents {
    static func watch(wake: @escaping @MainActor () -> Void,
                      launch: @escaping @MainActor () -> Void,
                      terminate: @escaping @MainActor () -> Void) -> SoloistCancellation {
        let center = NSWorkspace.shared.notificationCenter
        let wakeToken = NotificationToken(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in wake() } }, center: center)
        let launchToken = NotificationToken(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in launch() } }, center: center)
        let terminationToken = NotificationToken(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { terminate() } }, center: .default)
        return SoloistCancellation { _ = (wakeToken, launchToken, terminationToken) }
    }

    static func answers(port: Int) async -> Bool {
        guard let url = URL(string: "ws://127.0.0.1:\(port)") else { return false }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        let socket = session.webSocketTask(with: url)
        socket.resume()
        defer {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(3))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { timeout.cancel() }
        return await withTaskCancellationHandler {
            do {
                try await socket.send(.string("{\"type\":\"command\",\"command\":\"get_state\"}"))
                _ = try await socket.receive()
                return !Task.isCancelled
            } catch { return false }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }
}
