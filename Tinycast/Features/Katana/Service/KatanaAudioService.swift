import Foundation
import Observation

@MainActor
@Observable
final class KatanaAudioService {
    enum Activity: Equatable { case idle, tuning, recording }

    private(set) var activity = Activity.idle
    private(set) var reading: KatanaPitchEngine.Reading?
    private(set) var lastRecording: KatanaRecording?
    private(set) var isEnabled = false
    @ObservationIgnored private let transport: (any KatanaAudioTransport)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var operation: UUID?
    @ObservationIgnored private var destination: KatanaRecording.Destination?

    init(transport: (any KatanaAudioTransport)? = nil) { self.transport = transport }

    func start() { isEnabled = true }

    func stop() {
        isEnabled = false
        generation = UUID()
        transport?.stop()
        activity = .idle
        reading = nil
        lastRecording = nil
        destination = nil
    }

    func tune() async throws {
        guard activity != .recording else { throw KatanaError.busy }
        try await perform { transport, generation, connection in
            self.activity = .tuning
            let frame = try await transport.drySamples()
            try self.validate(generation, connection: connection)
            let reading = await Self.detect(frame.samples, sampleRate: frame.sampleRate)
            try self.validate(generation, connection: connection)
            self.reading = reading
        }
    }

    func startRecording(_ destination: KatanaRecording.Destination) async throws {
        guard activity == .idle else { throw KatanaError.busy }
        try await perform { transport, generation, connection in
            try await transport.beginRecording(destination)
            try self.validate(generation, connection: connection)
            self.lastRecording = nil
            self.destination = destination
            self.activity = .recording
        }
    }

    func finishRecording() async throws -> KatanaRecording {
        guard activity == .recording else { throw KatanaError.invalidData }
        var result: KatanaRecording?
        try await perform { transport, generation, connection in
            let recording = try await transport.finishRecording()
            try self.validate(generation, connection: connection)
            guard recording.sampleRate.isFinite, (8_000...192_000).contains(recording.sampleRate),
                  recording.frames > 0, recording.wet == self.destination?.wet,
                  recording.dry == self.destination?.dry else { throw KatanaError.invalidData }
            self.lastRecording = recording
            self.activity = .idle
            self.destination = nil
            result = recording
        }
        guard let result else { throw KatanaError.invalidData }
        return result
    }

    func stopTuning() {
        guard activity == .tuning else { return }
        generation = UUID()
        transport?.stop()
        activity = .idle
        reading = nil
    }

    private func validate(_ generation: UUID, connection: UUID) throws {
        try Task.checkCancellation()
        guard isEnabled, self.generation == generation, transport?.connectionID == connection else {
            throw CancellationError()
        }
    }

    private func perform(_ action: @MainActor (any KatanaAudioTransport, UUID, UUID) async throws -> Void) async throws {
        guard isEnabled else { throw KatanaError.disabled }
        guard operation == nil else { throw KatanaError.busy }
        guard let transport, let connection = transport.connectionID else {
            self.transport?.stop()
            activity = .idle
            reading = nil
            destination = nil
            throw KatanaError.unavailable
        }
        guard transport.isUSB else { throw KatanaError.usbRequired }
        let id = UUID(), generation = generation
        operation = id
        defer { if operation == id { operation = nil } }
        do {
            try validate(generation, connection: connection)
            try await action(transport, generation, connection)
        } catch {
            transport.stop()
            if self.generation == generation {
                activity = .idle
                reading = nil
                destination = nil
            }
            throw error
        }
    }

    @concurrent
    private static func detect(_ samples: [Float], sampleRate: Double) async -> KatanaPitchEngine.Reading? {
        KatanaPitchEngine.detect(samples, sampleRate: sampleRate)
    }
}
