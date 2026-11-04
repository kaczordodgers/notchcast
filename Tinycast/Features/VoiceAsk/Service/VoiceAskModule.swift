import Foundation
import Observation

@MainActor
@Observable
final class VoiceAskModule: NotchcastModule {
    var destination: String { didSet { defaults.set(destination, forKey: "voiceAsk.destination"); cancel() } }
    var keyCode: Int64 { didSet { defaults.set(keyCode, forKey: "voiceAsk.keyCode"); cancel() } }
    private(set) var result: VoiceAskResult?
    private(set) var failure: String?
    private(set) var enabled = false
    private var hold = VoiceAskHold()
    private var isProcessing = false
    private let defaults: UserDefaults
    private var transport: (any VoiceAskTransport)?
    private let beginRecording: @MainActor () async throws -> Void
    private let finishRecording: @MainActor () async throws -> String
    private let cancelRecording: @MainActor () -> Void
    private var task: Task<Void, Never>?
    private var identity = UUID()
    var onStart: (@MainActor () -> Void)?
    var onStop: (@MainActor () -> Void)?

    init(defaults: UserDefaults, begin: @escaping @MainActor () async throws -> Void,
         finish: @escaping @MainActor () async throws -> String,
         cancel: @escaping @MainActor () -> Void) {
        self.defaults = defaults
        beginRecording = begin
        finishRecording = finish
        cancelRecording = cancel
        destination = defaults.string(forKey: "voiceAsk.destination") ?? ""
        keyCode = (defaults.object(forKey: "voiceAsk.keyCode") as? Int64) ?? 105
    }

    func configure(transport: (any VoiceAskTransport)?) {
        cancel()
        self.transport = transport
    }

    func start() { guard !enabled else { return }; enabled = true; onStart?() }
    func stop() { enabled = false; onStop?(); cancel() }

    func press(alone: Bool) {
        guard enabled, transport != nil, !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hold.state == .idle, !isProcessing else { return }
        cancel()
        failure = nil
        hold.press(alone: alone)
        let current = identity
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard let self, identity == current, !Task.isCancelled,
                      hold.threshold() == .begin else { return }
                try await beginRecording()
            } catch {
                guard let self, identity == current, !Task.isCancelled else { return }
                failure = error.localizedDescription
                cancel()
            }
        }
    }

    func chord() {
        guard hold.state != .idle else { return }
        let action = hold.chord()
        if action == .cancel { cancelRecording() }
        task?.cancel()
        identity = UUID()
    }

    func release() {
        guard !isProcessing else { return }
        guard hold.release() == .finish else { task?.cancel(); return }
        isProcessing = true
        let pending = task
        let current = identity
        let destination = destination
        guard let transport else { cancel(); return }
        task = Task { [weak self] in
            await pending?.value
            guard let self, identity == current, enabled, !Task.isCancelled else { return }
            defer { if identity == current { isProcessing = false } }
            do {
                let text = try await finishRecording()
                try Task.checkCancellation()
                guard identity == current, self.destination == destination else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let reply = try await transport.send(text, destination: destination)
                try Task.checkCancellation()
                guard identity == current, enabled, self.destination == destination else { return }
                result = reply
            } catch {
                guard identity == current, !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
    }

    private func cancel() {
        isProcessing = false
        identity = UUID()
        task?.cancel()
        task = nil
        hold.reset()
        cancelRecording()
    }

    isolated deinit { task?.cancel() }
}
