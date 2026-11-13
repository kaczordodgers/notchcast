// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Service/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/Date+CaptureFileName.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/Service/*.swift
// notchcast-kit: core
import AppKit

extension CaptureEditorCoordinator {
    static let shared = CaptureEditorCoordinator(pasteboard: .withUniqueName())
}

@MainActor final class ScreenshotModule {
    static let shared = ScreenshotModule()
    var didCapture: (NSImage) -> Void = { _ in }
}

@main
struct ScreenshotOutputTest {
    static func main() async throws {
        try await lastCapture()
        let zone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 0)
        let stem = "Screenshot 1970-01-01 at 00.00.00"
        precondition(date.captureFileName(kind: "Screenshot", extension: "png", timeZone: zone) == "\(stem).png")
        precondition(date.captureFileName(
            kind: "Screenshot", extension: "png", timeZone: zone, collision: 2) == "\(stem) (2).png")
        precondition(ScreenshotRequest.isValid(rect: CGRect(x: -100, y: -200, width: 20, height: 30)))
        precondition(!ScreenshotRequest.isValid(rect: .zero))
        precondition(!ScreenshotRequest.isValid(rect: CGRect(x: CGFloat.infinity, y: 0, width: 20, height: 30)))
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
        var reported: URL?
        let saved = try await ScreenshotService.output(original, destination: .both(folder: folder), writeClipboard: { _ in
            guard let written = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
                preconditionFailure("Missing screenshot folder")
            }
            precondition(written.count == 3, "File must exist before clipboard write")
            return false
        }, clipboardFailure: { reported = $0 })
        precondition(saved != nil && saved == reported)
        let savedData = try Data(contentsOf: saved!)
        precondition(savedData == original)
        let missing = folder.appendingPathComponent("missing")
        do {
            _ = try await ScreenshotService.save(original, folder: missing, date: date, timeZone: zone)
            preconditionFailure("Missing destination must fail")
        } catch CocoaError.fileNoSuchFile {}
        print("✓ screenshot output: naming, rect validation, collision preservation, write errors")
        let cancelledFolder = folder.appending(path: "cancelled")
        try FileManager.default.createDirectory(at: cancelledFolder, withIntermediateDirectories: false)
        var clipboardWrites = 0
        let size = 64 * 1024 * 1024
        let saving = Task { @MainActor in
            try await ScreenshotService.output(Data(repeating: 42, count: size),
                destination: .both(folder: cancelledFolder), writeClipboard: { _ in
                    clipboardWrites += 1
                    return true
                }, clipboardFailure: { _ in })
        }
        // Enqueued after `output`, so it runs once `output` waits on the off-main save. It holds the main actor
        // until the file is fully written, then cancels: `output` resumes only after both, every time.
        let canceller = Task { @MainActor in
            let deadline = Date().addingTimeInterval(30)
            while true {
                let names = try FileManager.default.contentsOfDirectory(atPath: cancelledFolder.path)
                if let name = names.first, try FileManager.default.attributesOfItem(
                    atPath: cancelledFolder.appending(path: name).path)[.size] as? Int == size { break }
                precondition(Date() < deadline, "Save never finished writing")
                usleep(1000)
            }
            saving.cancel()
        }
        let result = await saving.result
        try await canceller.value
        precondition(clipboardWrites == 0, "Cancelled save replaced clipboard")
        guard case .failure(let error) = result, error is CancellationError else {
            preconditionFailure("Cancelled save must report cancellation")
        }
        print("PASS: cancellation during save preserves clipboard")
    }

    @MainActor static func lastCapture() async throws {
        var captured: NSImage?
        ScreenshotModule.shared.didCapture = { captured = $0 }
        defer { ScreenshotModule.shared.didCapture = { _ in } }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for destination in [ScreenshotRequest.Destination.clipboard, .file(folder: folder), .both(folder: folder)] {
            captured = nil
            _ = try await ScreenshotService.output(png, destination: destination,
                writeClipboard: { _ in true }, clipboardFailure: { _ in })
            precondition(captured?.size == CGSize(width: 12, height: 8),
                         "Successful screenshot must deliver the captured image")
        }
        let previous = captured
        do {
            _ = try await ScreenshotService.output(png, destination: .clipboard,
                writeClipboard: { _ in false }, clipboardFailure: { _ in })
            preconditionFailure("Failed clipboard-only capture must throw")
        } catch ScreenshotRequest.Failure.clipboardFailed {}
        precondition(captured === previous, "Failed capture must not deliver an image")
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ScreenshotService.output(png, destination: .clipboard,
                writeClipboard: { _ in preconditionFailure("Cancelled capture wrote clipboard") },
                clipboardFailure: { _ in })
        }
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled capture must throw")
        } catch is CancellationError {}
        precondition(captured === previous, "Cancelled capture must not deliver an image")
        _ = try await ScreenshotService.output(png, destination: .both(folder: folder),
            writeClipboard: { _ in false }, clipboardFailure: { _ in })
        precondition(captured !== previous, "Saved screenshot survives clipboard failure")
        print("PASS: successful screenshots deliver captured images; failures and cancellation do not")
    }
}
