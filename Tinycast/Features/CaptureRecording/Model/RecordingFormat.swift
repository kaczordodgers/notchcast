struct RecordingFormat: Sendable, Equatable {
    enum Track: Sendable { case video, systemAudio }
    let width: Int
    let height: Int
    let frameRate: Int
}
