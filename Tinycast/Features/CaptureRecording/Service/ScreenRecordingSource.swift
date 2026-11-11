import ScreenCaptureKit

@MainActor
final class ScreenRecordingSource: RecordingSource {
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private var stream: SCStream?
    private var tap: RecordingStreamTap?
    private let queue = DispatchQueue(label: "app.notchcast.recording", qos: .userInitiated)
    private let hasAccess: () -> Bool
    private let requestAccess: () -> Bool

    init(
        hasAccess: @escaping () -> Bool = ScreenRecordingAccess.isGranted,
        requestAccess: @escaping () -> Bool = ScreenRecordingAccess.request
    ) {
        self.hasAccess = hasAccess
        self.requestAccess = requestAccess
    }

    func prepare(_ target: RecordingTarget, frameRate: Int) async throws -> RecordingFormat {
        guard frameRate == 30 || frameRate == 60 else { throw RecordingTarget.Failure.invalidTarget }
        guard hasAccess() || requestAccess() else { throw RecordingTarget.Failure.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let configuration = SCStreamConfiguration()
        let filter: SCContentFilter
        let size: CGSize
        switch target {
        case .area(let rect):
            guard RecordingTarget.isValid(rect) else { throw RecordingTarget.Failure.invalidTarget }
            guard let display = content.displays.first(where: { $0.frame.contains(rect) }) else {
                throw RecordingTarget.Failure.targetUnavailable
            }
            filter = displayFilter(display, content: content)
            configuration.sourceRect = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            size = rect.size
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw RecordingTarget.Failure.targetUnavailable
            }
            filter = displayFilter(display, content: content)
            size = filter.contentRect.size
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw RecordingTarget.Failure.targetUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
            size = filter.contentRect.size
        }
        let width = Int((size.width * CGFloat(filter.pointPixelScale)).rounded(.up))
        let height = Int((size.height * CGFloat(filter.pointPixelScale)).rounded(.up))
        guard width > 0, height > 0, width <= 16_384, height <= 16_384 else {
            throw RecordingTarget.Failure.invalidTarget
        }
        configuration.width = width + width % 2
        configuration.height = height + height % 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.captureDynamicRange = .SDR
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = true
        configuration.showMouseClicks = false
        configuration.captureMicrophone = false
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.queueDepth = 3
        self.filter = filter
        self.configuration = configuration
        return RecordingFormat(width: configuration.width, height: configuration.height, frameRate: frameRate)
    }

    func start(writer: any RecordingWriting, onFailure: @escaping @MainActor (any Error) -> Void) async throws {
        try Task.checkCancellation()
        guard stream == nil, let filter, let configuration else { throw RecordingTarget.Failure.invalidTarget }
        let tap = RecordingStreamTap(writer: writer) { error in
            Task { @MainActor in onFailure(error) }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: tap)
        self.tap = tap
        self.stream = stream
        try stream.addStreamOutput(tap, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(tap, type: .audio, sampleHandlerQueue: queue)
        writer.begin(at: CMClockGetTime(CMClockGetHostTimeClock()))
        try await stream.startCapture()
        try Task.checkCancellation()
    }

    func stop() async throws {
        tap?.silence()
        let stream = stream
        self.stream = nil
        defer { tap = nil; filter = nil; configuration = nil }
        var failure: (any Error)?
        do { try await stream?.stopCapture() } catch { failure = error }
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
        if let failure { throw failure }
    }

    private func displayFilter(_ display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let applications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        return SCContentFilter(display: display, excludingApplications: applications, exceptingWindows: [])
    }
}
