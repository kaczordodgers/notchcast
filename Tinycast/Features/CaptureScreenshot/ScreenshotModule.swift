import Foundation
import Observation

@MainActor
@Observable
final class ScreenshotModule: NotchcastModule {
    enum Destination: String, CaseIterable {
        case clipboard, file, both
    }

    typealias Capture = @MainActor (
        ScreenshotRequest, ScreenshotRequest.Destination, @MainActor () -> Bool
    ) async throws -> URL?

    var destination: Destination {
        didSet {
            defaults.set(destination.rawValue, forKey: Self.destinationKey)
            cancelCapture()
        }
    }
    var folder: URL? {
        didSet {
            defaults.set(folder?.path, forKey: Self.folderKey)
            cancelCapture()
        }
    }
    private let defaults: UserDefaults
    private let capture: Capture
    let area: CaptureAreaService
    private(set) var enabled = false
    private var operation: UUID?
    private var captureTask: Task<URL?, Error>?
    var commandTask: Task<Void, Never>?
    private static let destinationKey = "notchcast.screenshot.destination"
    private static let folderKey = "notchcast.screenshot.folder"

    init(
        defaults: UserDefaults = UserDefaults(suiteName:
            (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!,
        area: CaptureAreaService = CaptureAreaService(),
        capture: @escaping Capture = { request, destination, isEnabled in
            try await ScreenshotService.capture(request, destination: destination, isEnabled: isEnabled)
        }
    ) {
        self.defaults = defaults
        self.area = area
        self.capture = capture
        destination = defaults.string(forKey: Self.destinationKey).flatMap(Destination.init(rawValue:)) ?? .clipboard
        folder = defaults.string(forKey: Self.folderKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    func start() { enabled = true }

    func stop() {
        enabled = false
        area.stop()
        commandTask?.cancel()
        commandTask = nil
        cancelCapture()
    }

    func capture(_ request: ScreenshotRequest) async throws -> URL? {
        try Task.checkCancellation()
        guard enabled else { throw ScreenshotRequest.Failure.disabled }
        cancelCapture()
        let identity = UUID()
        operation = identity
        let destination = outputDestination
        let task = Task { [weak self, capture] in
            try await capture(request, destination) { [weak self] in
                self?.enabled == true && self?.operation == identity
            }
        }
        captureTask = task
        defer {
            if operation == identity { operation = nil; captureTask = nil }
        }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        guard operation == identity else { throw CancellationError() }
        return result
    }

    static func failureMessage(_ error: any Error) -> String {
        let failure = error as NSError
        if failure.domain == NSCocoaErrorDomain && (512..<1024).contains(failure.code) {
            return String(localized: "Could not save the screenshot.", table: "Notchcast")
        }
        let shared: CaptureFailure = switch error {
        case let shared as CaptureFailure: shared
        case ScreenshotRequest.Failure.permissionDenied: .permissionDenied
        case ScreenshotRequest.Failure.clipboardFailed: .clipboardFailed
        case ScreenshotRequest.Failure.disabled: .disabled
        case ScreenshotRequest.Failure.invalidRect, ScreenshotRequest.Failure.targetUnavailable: .areaUnavailable
        default: .captureFailed
        }
        return shared.message
    }

    private var outputDestination: ScreenshotRequest.Destination {
        switch destination {
        case .clipboard: .clipboard
        case .file: .file(folder: folder)
        case .both: .both(folder: folder)
        }
    }

    private func cancelCapture() {
        operation = nil
        captureTask?.cancel()
        captureTask = nil
    }

    isolated deinit { captureTask?.cancel(); commandTask?.cancel() }
}
