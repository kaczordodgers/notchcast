import CoreMedia

protocol RecordingWriting: AnyObject, Sendable {
    func begin(at time: CMTime)
    func append(_ sample: CMSampleBuffer, track: RecordingFormat.Track) throws
    func setPaused(_ paused: Bool, at time: CMTime)
    func finish(at time: CMTime) async throws
    func cancel() async
}
