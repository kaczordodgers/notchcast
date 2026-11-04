import CoreMedia

@MainActor
protocol RecordingSource: AnyObject {
    func prepare(_ target: RecordingTarget, frameRate: Int) async throws -> RecordingFormat
    func start(writer: any RecordingWriting, onFailure: @escaping @MainActor (any Error) -> Void) async throws
    func stop() async throws
}
