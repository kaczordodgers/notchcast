import AppKit

@MainActor
final class ScrollingCaptureModule: NotchcastModule {
    private let area: CaptureAreaService
    private let session: ScrollingCaptureSession
    private let write: (Data) -> Bool
    private var enabled = false
    private var task: Task<Void, Never>?

    init(
        area: CaptureAreaService = CaptureAreaService(),
        session: ScrollingCaptureSession = ScrollingCaptureSession(),
        write: @escaping (Data) -> Bool = {
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setData($0, forType: .png)
        }
    ) {
        self.area = area
        self.session = session
        self.write = write
    }

    func start() { enabled = true }
    func stop() {
        enabled = false
        task?.cancel()
        task = nil
        area.stop()
        session.cancel()
    }

    func capture(report: @escaping (String) -> Void) {
        guard enabled else { return }
        if session.state == .capturing {
            task?.cancel()
            task = Task { [weak self] in await self?.finish(report: report) }
            return
        }
        guard task == nil else { return }
        do {
            try area.start { [weak self] selection in
                guard let self, self.enabled, let selection else { return }
                do {
                    try self.session.start(rect: selection.rect, displayID: selection.displayID)
                    report(String(localized: "Scroll the area, then run Scrolling Capture again to copy."))
                    self.task = Task { [weak self] in
                        do {
                            while let self, self.session.state == .capturing {
                                try await Task.sleep(for: .milliseconds(100))
                            }
                            try Task.checkCancellation()
                            await self?.finish(report: report)
                        } catch {}
                    }
                } catch { report(Self.failureMessage(error)) }
            }
        } catch { report(Self.failureMessage(error)) }
    }

    private func finish(report: (String) -> Void) async {
        defer { if !Task.isCancelled { task = nil } }
        do {
            let image = try await session.stop()
            try Task.checkCancellation()
            guard enabled, let image else { return }
            let limited = session.state == .limitReached
            let data = try await ScrollingCaptureSession.pngData(for: image)
            try Task.checkCancellation()
            guard enabled else { return }
            guard write(data) else { report(String(localized: "Could not copy to clipboard.")); return }
            if limited { report(String(localized: "Scrolling capture reached the 20,000 pixel limit.")) }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            report(Self.failureMessage(error))
        }
    }

    isolated deinit { task?.cancel() }

    static func failureMessage(_ error: any Error) -> String {
        if error is CaptureAreaService.Failure { return String(localized: "Screen Recording access is required.") }
        switch error as? ScrollingCaptureSession.Failure {
        case .permissionDenied: return String(localized: "Screen Recording access is required.")
        case .invalidRect, .displayUnavailable: return String(localized: "Capture area is unavailable.")
        default: return String(localized: "Could not capture the screen.")
        }
    }
}
