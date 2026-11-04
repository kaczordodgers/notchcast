import Foundation

@MainActor
protocol KatanaAudioTransport: AnyObject {
    var connectionID: UUID? { get }
    var isUSB: Bool { get }
    func drySamples() async throws -> (samples: [Float], sampleRate: Double)
    func beginRecording(_ destination: KatanaRecording.Destination) async throws
    func finishRecording() async throws -> KatanaRecording
    func stop()
}
