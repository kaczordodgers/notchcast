import AppKit

@main
struct ScreenshotOutputTest {
    static func main() async throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 0)
        let stem = ScreenshotFilename.stem(date: date, timeZone: zone)
        precondition(stem == "Screenshot 1970-01-01 at 00.00.00")
        precondition(ScreenshotFilename.name(stem: stem, collision: 2) == "\(stem) (2).png")
        precondition(ScreenshotFilename.isValid(rect: CGRect(x: -100, y: -200, width: 20, height: 30)))
        precondition(!ScreenshotFilename.isValid(rect: .zero))
        precondition(!ScreenshotFilename.isValid(rect: CGRect(x: CGFloat.infinity, y: 0, width: 20, height: 30)))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        do {
            _ = try await ScreenshotService.capture(.display(0), destination: .clipboard, pasteboard: board) { false }
            preconditionFailure("Disabled capture must fail before requesting permission")
        } catch ScreenshotRequest.Failure.disabled {}
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = Data([1, 2, 3])
        let first = try await ScreenshotService.save(original, folder: folder, date: date, timeZone: zone)
        let second = try await ScreenshotService.save(Data([4]), folder: folder, date: date, timeZone: zone)
        precondition(first.lastPathComponent == "\(stem).png")
        precondition(second.lastPathComponent == "\(stem) (1).png")
        let preserved = try Data(contentsOf: first)
        precondition(preserved == original)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ScreenshotService.save(original, folder: folder, date: date, timeZone: zone)
        }
        do {
            _ = try await task.value
            preconditionFailure("Cancelled output must not write")
        } catch is CancellationError {}
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        precondition(files.count == 2)
        let missing = folder.appendingPathComponent("missing")
        do {
            _ = try await ScreenshotService.save(original, folder: missing, date: date, timeZone: zone)
            preconditionFailure("Missing destination must fail")
        } catch CocoaError.fileNoSuchFile {}
        print("✓ screenshot output: naming, rect validation, collision preservation, write errors")
    }
}
