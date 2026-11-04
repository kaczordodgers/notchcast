@MainActor
protocol VoiceAskTransport {
    func send(_ text: String, destination: String) async throws -> VoiceAskResult
}
