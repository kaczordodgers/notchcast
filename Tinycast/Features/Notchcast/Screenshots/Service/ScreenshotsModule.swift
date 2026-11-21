import CoreGraphics
import Foundation

/// Runs one capture or edit at a time; a trigger while one is active, the editor included, is ignored.
@MainActor
final class ScreenshotsModule: NotchcastModule {
    enum Scope { case area, display, text }

    static let switchID = ScreenshotsAddon.switches[0].id
    static let editAfterCaptureKey = "notchcast.screenshot.editAfterCapture"
    static let textSymbol = "text.viewfinder"
    static let textNoticeID = "screenshot.text"
    static let scrollingID = "screenshot.scrolling"
    static let finishScrollingTitle = String(localized: "Finish Scrolling Capture", table: "NotchcastScreenshots")
    static let cancelScrollingTitle = String(localized: "Cancel Scrolling Capture", table: "NotchcastScreenshots")
    private let context: NotchcastContext
    private let system: ScreenshotSystem
    private let exclusion: ScreenshotExclusion
    private var running = false
    private var session: Task<Void, Never>?
    private var operation: UUID?
    private var closeSurface: (@MainActor () -> Void)?
    /// The last capture as PNG, so Edit Last Screenshot never holds a full bitmap between edits.
    private var lastCapture: (png: Data, scale: CGFloat)?
    private var closeEditor: (@MainActor () -> Void)?
    private var export: Task<Void, Never>?
    private var warmUp: Task<Void, Never>?
    private var scrolling = ScrollingCapturePhase.idle
    private var scrollingFinish: ScrollingFinishFlag?
    private var scrollingHeight: Int?
    private var hideGuide: (@MainActor () -> Void)?

    init(context: NotchcastContext, system: ScreenshotSystem,
         exclusion: ScreenshotExclusion = ScreenshotExclusion(
            pid: ProcessInfo.processInfo.processIdentifier, bundleID: Bundle.main.bundleIdentifier)) {
        self.context = context
        self.system = system
        self.exclusion = exclusion
    }

    func start() {
        running = true
        let warm = system.warmTextRecognition
        warmUp = Task.detached(priority: .utility) { await warm() }
    }

    func stop() {
        running = false
        operation = nil
        session?.cancel()
        session = nil
        warmUp?.cancel()
        warmUp = nil
        context.presenter.end(notice: Self.textNoticeID)
        endScrolling()
        closeSurface?()
        export?.cancel()
        export = nil
        endEditing()
        lastCapture = nil
    }

    func captureArea() { begin(.area) }

    func captureDisplay() { begin(.display) }

    func captureText() { begin(.text) }

    /// Starts a run, or finishes the one capturing; a result never opens the editor by itself.
    func captureScrolling() {
        switch scrolling.command {
        case .finish: return finishScrolling()
        case .ignore: return
        case .start: break
        }
        guard isIdle else { return }
        guard system.grantAccess() else { return report(ScreenshotRequest.Failure.permissionDenied) }
        scrolling = .selecting
        run { [self] id in
            defer { if operation == id { endScrolling() } }
            guard let region = try await selectRegion() else { return }
            let finish = ScrollingFinishFlag()
            scrollingFinish = finish
            scrolling = .capturing
            hideGuide = system.showGuide(region)
            showScrolling(height: nil)
            context.presenter.setMenuRows([
                IslandMenuRow(id: "finish", title: Self.finishScrollingTitle),
                IslandMenuRow(id: "cancel", title: Self.cancelScrollingTitle),
            ], owner: Self.scrollingID) { [weak self] row in
                if row == "cancel" { self?.cancelScrolling() } else { self?.finishScrolling() }
            }
            let source = try await system.openRegion(region)
            try Task.checkCancellation()
            let result = try await ScrollingCaptureRun.run(
                source, finish: finish, uptime: system.uptime, pause: system.pause,
                progress: { [weak self] height in
                    guard let self, operation == id else { return }
                    showScrolling(height: height)
                })
            let data = try await ScreenshotFiles.png(result.image, scale: region.scale)
            try Task.checkCancellation()
            lastCapture = (data, region.scale)
            let saved = try await output(data)
            try Task.checkCancellation()
            endScrolling()
            context.presenter.post(ScreenshotNotices.scrolling(result.ending, saved: saved), onTap: nil)
        }
    }

    func editLastCapture() {
        guard isIdle else { return }
        guard let lastCapture else { return report(ScreenshotRequest.Failure.nothingToEdit) }
        run { [self] _ in
            guard let image = await ScreenshotFiles.decode(lastCapture.png) else {
                throw ScreenshotRequest.Failure.encodingFailed
            }
            try Task.checkCancellation()
            edit(image, scale: lastCapture.scale)
        }
    }

    private var isIdle: Bool { running && session == nil && closeEditor == nil }

    private func begin(_ scope: Scope) {
        guard isIdle else { return }
        guard system.grantAccess() else {
            if scope == .text { system.openScreenRecordingSettings() }
            return report(ScreenshotRequest.Failure.permissionDenied)
        }
        run { [self] _ in
            guard let shot = try await capture(scope) else { return }
            if scope == .text { return try await copyText(in: shot.image) }
            let data = try await ScreenshotFiles.png(shot.image, scale: shot.scale)
            try Task.checkCancellation()
            lastCapture = (data, shot.scale)
            if context.defaults.bool(forKey: Self.editAfterCaptureKey) {
                edit(shot.image, scale: shot.scale)
            } else {
                try await output(data)
            }
        }
    }

    private func run(_ work: @escaping @MainActor @Sendable (UUID) async throws -> Void) {
        let id = UUID()
        operation = id
        session = Task {
            do {
                try await work(id)
            } catch {
                if operation == id, !(error is CancellationError) { report(error) }
            }
            guard operation == id else { return }
            operation = nil
            session = nil
        }
    }

    /// The picture with its pixels per point, read from the display it was frozen on.
    private func capture(_ scope: Scope) async throws -> (image: CGImage, scale: CGFloat)? {
        switch scope {
        case .display:
            guard let display = try await system.freeze(system.cursor(), exclusion).first else {
                throw ScreenshotRequest.Failure.targetUnavailable
            }
            return (display.image, display.scale)
        case .area, .text:
            guard let picked = try await pick() else { return nil }
            return try capture(picked.request, in: picked.frozen, windows: picked.windows, frames: picked.offered)
        }
    }

    private struct Selection {
        let request: ScreenshotRequest
        let frozen: [ScreenshotFrozenDisplay]
        let windows: [UInt32: CGImage]
        let offered: [ScreenshotWindow]
    }

    /// Every display frozen and every pickable window with it, then the user's pick; nil when cancelled.
    private func pick() async throws -> Selection? {
        let frozen = try await system.freeze(nil, exclusion)
        try Task.checkCancellation()
        let pickable = exclusion.pickable(system.windows())
        let windows = try await system.freezeWindows(pickable.map(\.id))
        try Task.checkCancellation()
        let offered = pickable.filter { windows[$0.id] != nil }
        guard let request = await select(frozen, offered) else { return nil }
        try Task.checkCancellation()
        return Selection(request: request, frozen: frozen, windows: windows, offered: offered)
    }

    /// Only the area leaves this call, so the frozen displays are let go before the run starts.
    private func selectRegion() async throws -> ScrollingCaptureRegion? {
        guard let picked = try await pick() else { return nil }
        guard let region = ScrollingCaptureRegion(picked.request, displays: picked.frozen, windows: picked.offered)
        else { throw ScreenshotRequest.Failure.targetUnavailable }
        return region
    }

    /// The island's stop and the stitched height; once Finish is asked it takes no more presses.
    private func showScrolling(height: Int?) {
        scrollingHeight = height
        var onTap: (@MainActor () -> Void)?
        if scrolling == .capturing { onTap = { [weak self] in self?.finishScrolling() } }
        context.presenter.setStatus(
            IslandStatus(id: Self.scrollingID, symbol: "stop.circle", text: height.map(ScrollingCapturePhase.heightText),
                         label: Self.finishScrollingTitle),
            for: Self.scrollingID, onTap: onTap)
    }

    private func finishScrolling() {
        guard scrolling == .capturing, let scrollingFinish else { return }
        scrollingFinish.request()
        scrolling = .finishing
        context.presenter.setMenuRows([], owner: Self.scrollingID) { _ in }
        showScrolling(height: scrollingHeight)
    }

    private func cancelScrolling() {
        guard scrolling == .capturing else { return }
        operation = nil
        session?.cancel()
        session = nil
        endScrolling()
    }

    private func endScrolling() {
        guard scrolling != .idle else { return }
        scrolling = .idle
        scrollingFinish = nil
        scrollingHeight = nil
        hideGuide?()
        hideGuide = nil
        context.presenter.setStatus(nil, for: Self.scrollingID, onTap: nil)
        context.presenter.setMenuRows([], owner: Self.scrollingID) { _ in }
    }

    private func select(_ frozen: [ScreenshotFrozenDisplay], _ windows: [ScreenshotWindow]) async
        -> ScreenshotRequest? {
        await withCheckedContinuation { continuation in
            closeSurface = system.select(frozen, windows) { [weak self] request in
                self?.closeSurface = nil
                continuation.resume(returning: request)
            }
        }
    }

    private func capture(
        _ request: ScreenshotRequest, in frozen: [ScreenshotFrozenDisplay], windows: [UInt32: CGImage],
        frames: [ScreenshotWindow]
    ) throws -> (image: CGImage, scale: CGFloat) {
        switch request {
        case .rect(let rect):
            guard ScreenshotRequest.isValid(rect: rect) else { throw ScreenshotRequest.Failure.invalidRect }
            guard let display = frozen.first(where: { $0.frame.contains(rect) }),
                let image = ScreenshotGeometry.crop(display, to: rect)
            else { throw ScreenshotRequest.Failure.targetUnavailable }
            return (image, display.scale)
        case .window(let id):
            guard let image = windows[id] else { throw ScreenshotRequest.Failure.targetUnavailable }
            let points = frames.first { $0.id == id }?.frame.width ?? 0
            return (image, points > 0 ? max(1, (CGFloat(image.width) / points).rounded()) : 1)
        case .display(let id):
            guard let display = frozen.first(where: { $0.id == id }) else {
                throw ScreenshotRequest.Failure.targetUnavailable
            }
            return (display.image, display.scale)
        }
    }

    private func edit(_ image: CGImage, scale: CGFloat) {
        closeEditor = system.edit(image, scale) { [weak self] outcome in self?.finishEditing(outcome) }
    }

    /// The editor stays open until its result is written, so a failed write loses no annotation.
    private func finishEditing(_ outcome: CaptureEditorOutcome) {
        guard closeEditor != nil, export == nil else { return }
        let document: AnnotationDocument
        var chosen: URL?
        switch outcome {
        case .discard: return endEditing()
        case .close(let edited):
            guard edited.isDirty else { return endEditing() }
            return askToDiscard()
        case .copy(let edited), .save(let edited): document = edited
        case .saveAs(let edited):
            guard let url = system.chooseSaveFile(
                ScreenshotFileName.name(date: context.now(), timeZone: .current)) else { return }
            document = edited
            chosen = url
        }
        export = Task {
            do {
                let data = try await ScreenshotFiles.render(document)
                try Task.checkCancellation()
                let notice: IslandNotice
                if case .copy = outcome {
                    guard system.writeClipboard(data) else { throw ScreenshotRequest.Failure.clipboardFailed }
                    notice = ScreenshotNotices.copied
                } else {
                    let url = if let chosen {
                        try await ScreenshotFiles.write(data, to: chosen)
                    } else {
                        try await ScreenshotFiles.save(data, in: folder(), date: context.now(), timeZone: .current)
                    }
                    notice = ScreenshotNotices.saved(url)
                }
                try Task.checkCancellation()
                endEditing()
                context.presenter.post(notice, onTap: nil)
            } catch {
                if !(error is CancellationError) { report(error) }
            }
            if !Task.isCancelled { export = nil }
        }
    }

    /// Our own dialog; with none to ask (no app running) the edits are kept.
    private func askToDiscard() {
        export = Task {
            let discard = await context.confirmDestructive?(
                String(localized: "Discard this screenshot's edits?", table: "NotchcastScreenshots"),
                String(localized: "It was not copied or saved yet.", table: "NotchcastScreenshots"),
                String(localized: "Discard", table: "NotchcastScreenshots")) ?? false
            guard !Task.isCancelled else { return }
            export = nil
            if discard { endEditing() }
        }
    }

    private func endEditing() {
        let close = closeEditor
        closeEditor = nil
        close?()
    }

    private func folder() throws -> URL {
        try context.defaults.string(forKey: ScreenshotBackupKeys.folder)
            .map { URL(filePath: $0, directoryHint: .isDirectory) } ?? system.downloads()
    }

    /// v1's order: the file first, so a failed clipboard write still leaves the picture saved.
    @discardableResult
    private func output(_ data: Data) async throws -> URL? {
        let destination = context.defaults.string(forKey: ScreenshotBackupKeys.destination)
            .flatMap(ScreenshotDestination.init(rawValue:)) ?? .clipboard
        var saved: URL?
        if destination != .clipboard {
            saved = try await ScreenshotFiles.save(data, in: folder(), date: context.now(), timeZone: .current)
        }
        if Task.isCancelled {
            if let saved { try? FileManager.default.removeItem(at: saved) }
            throw CancellationError()
        }
        if destination != .file, !system.writeClipboard(data), saved == nil {
            throw ScreenshotRequest.Failure.clipboardFailed
        }
        return saved
    }

    /// Only the text leaves: the image stays in memory and is never written to disk.
    /// Reposting the progress notice's id with the first line turns it into the result in place.
    private func copyText(in image: CGImage) async throws {
        context.presenter.post(IslandNotice(
            id: Self.textNoticeID, symbol: Self.textSymbol,
            text: String(localized: "Recognizing text…", table: "NotchcastScreenshots"),
            progress: IslandProgress(fraction: nil)), onTap: nil)
        let text: String
        do {
            await warmUp?.value
            try Task.checkCancellation()
            guard let lines = try? await system.recognizeText(image) else {
                try Task.checkCancellation()
                throw ScreenshotRequest.Failure.recognitionFailed
            }
            try Task.checkCancellation()
            guard let joined = ScreenText.join(lines) else { throw ScreenshotRequest.Failure.noText }
            guard system.writeText(joined) else { throw ScreenshotRequest.Failure.clipboardFailed }
            text = joined
        } catch {
            // A cancelled run belongs to a `stop()` that already ended it, maybe under a newer notice.
            if !Task.isCancelled { context.presenter.end(notice: Self.textNoticeID) }
            throw error
        }
        context.presenter.post(IslandNotice(
            id: Self.textNoticeID, symbol: Self.textSymbol, text: ScreenText.firstLine(of: text)), onTap: nil)
    }

    private func report(_ error: any Error) {
        context.presenter.post(IslandNotice(
            id: "screenshot.failed", symbol: "camera", text: ScreenshotRequest.failureMessage(error),
            isFailure: true), onTap: nil)
    }
}
