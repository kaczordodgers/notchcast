import AppKit
import ImageIO
import OSLog
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenshotService {
    static func hasScreenRecordingAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @MainActor
    @discardableResult
    static func capture(
        _ request: ScreenshotRequest,
        destination: ScreenshotRequest.Destination,
        pasteboard: NSPasteboard = .general,
        clipboardFailure: (URL) -> Void = { url in
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast", category: "Screenshot")
                .error("Clipboard write failed; screenshot saved at \(url.path, privacy: .private)")
        },
        isEnabled: @MainActor () -> Bool
    ) async throws -> URL? {
        guard isEnabled() else { throw ScreenshotRequest.Failure.disabled }
        guard hasScreenRecordingAccess() || requestScreenRecordingAccess() else {
            throw ScreenshotRequest.Failure.permissionDenied
        }
        let data = try await png(request)
        try Task.checkCancellation()
        return try await output(data, destination: destination, writeClipboard: { data in
            let item = NSPasteboardItem()
            guard item.setData(data, forType: .png) else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects([item])
        }, clipboardFailure: clipboardFailure)
    }

    @MainActor
    static func output(
        _ data: Data, destination: ScreenshotRequest.Destination,
        writeClipboard: (Data) -> Bool, clipboardFailure: (URL) -> Void
    ) async throws -> URL? {
        let url: URL?
        switch destination {
        case .clipboard: url = nil
        case .file(let folder), .both(let folder): url = try await save(data, folder: folder)
        }
        try Task.checkCancellation()
        switch destination {
        case .clipboard, .both:
            guard writeClipboard(data) else {
                if let url {
                    clipboardFailure(url)
                    return url
                }
                throw ScreenshotRequest.Failure.clipboardFailed
            }
        case .file:
            break
        }
        return url
    }

    @concurrent
    private static func png(_ request: ScreenshotRequest) async throws -> Data {
        try Task.checkCancellation()
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.ignoreShadows = true
        configuration.dynamicRange = .sdr
        let output: SCScreenshotOutput
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let ownApplications = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
                || $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        switch request {
        case .rect(let rect):
            guard ScreenshotRequest.isValid(rect: rect) else {
                throw ScreenshotRequest.Failure.invalidRect
            }
            guard let display = content.displays.first(where: { $0.frame.contains(rect) }) else {
                throw ScreenshotRequest.Failure.targetUnavailable
            }
            let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            configuration.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        case .window, .display:
            let filter: SCContentFilter
            switch request {
            case .window(let id):
                guard let window = content.windows.first(where: { $0.windowID == id }) else {
                    throw ScreenshotRequest.Failure.targetUnavailable
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
            case .display(let id):
                guard let display = content.displays.first(where: { $0.displayID == id }) else {
                    throw ScreenshotRequest.Failure.targetUnavailable
                }
                filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            case .rect:
                throw ScreenshotRequest.Failure.invalidRect
            }
            output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        }
        try Task.checkCancellation()
        guard let image = output.sdrImage else { throw ScreenshotRequest.Failure.encodingFailed }
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenshotRequest.Failure.encodingFailed
        }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw ScreenshotRequest.Failure.encodingFailed }
        return data as Data
    }

    @concurrent
    static func save(
        _ data: Data, folder: URL?, date: Date = Date(), timeZone: TimeZone = .current
    ) async throws -> URL {
        let directory = try folder ?? FileManager.default.url(
            for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        var collision = 0
        while true {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent(date.captureFileName(
                kind: "Screenshot", extension: "png", timeZone: timeZone, collision: collision))
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                collision += 1
            }
        }
    }
}
