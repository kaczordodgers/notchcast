import Foundation

enum RecordingFiles {
    @concurrent
    static func workspace(in folder: URL) async throws -> URL {
        guard folder.isFileURL else { throw RecordingTarget.Failure.invalidFolder }
        try Task.checkCancellation()
        let directory = folder.appendingPathComponent(".recording-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    @concurrent
    static func publish(workspace: URL, date: Date, timeZone: TimeZone) async throws -> URL {
        let source = workspace.appendingPathComponent("capture.mp4")
        let folder = workspace.deletingLastPathComponent()
        var collision = 0
        while true {
            try Task.checkCancellation()
            let destination = folder.appendingPathComponent(
                RecordingNaming.filename(date: date, timeZone: timeZone, collision: collision))
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                if Task.isCancelled {
                    try FileManager.default.removeItem(at: destination)
                    throw CancellationError()
                }
                return destination
            } catch CocoaError.fileWriteFileExists {
                collision += 1
            }
        }
    }

    @concurrent
    static func discard(_ workspace: URL) async throws {
        try FileManager.default.removeItem(at: workspace)
    }
}
