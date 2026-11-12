import CoreMedia
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class RecordingModule: NotchcastModule {
    enum Phase: Equatable { case idle, countdown(Int), starting, recording, paused, stopping }
    typealias WriterFactory = @Sendable (URL, RecordingFormat) async throws -> any RecordingWriting

    private struct Session {
        let identity: UUID
        let source: any RecordingSource
        let date: Date
        let timeZone: TimeZone
        var workspace: URL?
        var writer: (any RecordingWriting)?
    }

    var frameRate: Int {
        get { storedFrameRate }
        set {
            storedFrameRate = newValue == 30 ? 30 : 60
            defaults.set(storedFrameRate, forKey: Self.frameRateKey)
        }
    }
    var folder: URL {
        didSet { defaults.set(folder.path, forKey: Self.folderKey) }
    }
    private(set) var phase = Phase.idle {
        didSet {
            if oldValue != phase,
                oldValue == .recording || oldValue == .paused || phase == .recording || phase == .paused {
                refreshCommands()
            }
        }
    }
    private(set) var lastError: (any Error)?
    private(set) var enabled = false
    private var requestedEnabled = false
    @ObservationIgnored let commandArea: CaptureAreaService
    @ObservationIgnored var commandTask: Task<Void, Never>?
    @ObservationIgnored private let refreshCommands: () -> Void
    @ObservationIgnored private var shutdownTask: Task<Void, Never>?
    private var storedFrameRate: Int
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeSource: @MainActor () -> any RecordingSource
    @ObservationIgnored private let makeWriter: WriterFactory
    @ObservationIgnored private let sleep: @Sendable () async throws -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private let hostTime: () -> CMTime
    @ObservationIgnored private var session: Session?
    @ObservationIgnored private var operation: UUID?
    @ObservationIgnored private var startTask: Task<Void, any Error>?
    @ObservationIgnored private var finishTask: Task<URL, any Error>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    private static let frameRateKey = "notchcast.recording.frameRate"
    private static let folderKey = "notchcast.recording.folder"

    init(
        defaults: UserDefaults = NotchcastIdentity.current.defaults,
        defaultFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
        commandArea: CaptureAreaService = CaptureAreaService(),
        refreshCommands: @escaping () -> Void = { NotchcastHost.current.refreshNotchcastCommands() },
        makeSource: @escaping @MainActor () -> any RecordingSource = { ScreenRecordingSource() },
        makeWriter: @escaping WriterFactory = { try await RecordingWriter.create(url: $0, format: $1) },
        sleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(1)) },
        now: @escaping () -> Date = { Date() },
        timeZone: @escaping () -> TimeZone = { .current },
        hostTime: @escaping () -> CMTime = { CMClockGetTime(CMClockGetHostTimeClock()) }
    ) {
        self.defaults = defaults
        self.commandArea = commandArea
        self.refreshCommands = refreshCommands
        self.makeSource = makeSource
        self.makeWriter = makeWriter
        self.sleep = sleep
        self.now = now
        self.timeZone = timeZone
        self.hostTime = hostTime
        storedFrameRate = defaults.integer(forKey: Self.frameRateKey) == 30 ? 30 : 60
        folder = defaults.string(forKey: Self.folderKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? defaultFolder
    }

    func start() {
        requestedEnabled = true
        enabled = true
    }

    func stop() { shutdown() }
    func stopForTermination(_ phase: NotchcastTerminationPhase) async {
        guard phase == .beforeRootDrain else { return }
        shutdown()
        await waitUntilIdle()
    }

    private func shutdown() {
        requestedEnabled = false
        commandArea.stop()
        guard shutdownTask == nil else { return }
        if phase == .recording || phase == .paused || phase == .stopping {
            let reportSave = !NotchcastPreferences.shared.isOn(.recording)
            shutdownTask = Task { [self] in
                defer { shutdownTask = nil }
                if phase == .recording || phase == .paused {
                    do {
                        _ = try await finish()
                        if reportSave {
                            NotchcastHost.current.showMessage(String(localized: "Recording saved", table: "Notchcast"), .success)
                        }
                    } catch {
                        lastError = error
                        if reportSave {
                            NotchcastHost.current.showMessage(Self.failureMessage(error), .danger)
                        }
                    }
                } else {
                    _ = await finishTask?.result
                }
                enabled = requestedEnabled
                refreshCommands()
            }
            return
        }
        enabled = false
        commandTask?.cancel()
        cancel()
        refreshCommands()
    }

    func record(_ target: RecordingTarget) async throws {
        try Task.checkCancellation()
        guard enabled else { throw RecordingTarget.Failure.disabled }
        guard phase == .idle else { throw RecordingTarget.Failure.busy }
        if case .area(let rect) = target, !RecordingTarget.isValid(rect) {
            throw RecordingTarget.Failure.invalidTarget
        }
        let identity = UUID()
        operation = identity
        lastError = nil
        session = Session(identity: identity, source: makeSource(), date: now(), timeZone: timeZone())
        phase = .countdown(3)
        let folder = folder
        let frameRate = frameRate
        let task = Task { [self] in
            defer { startTask = nil }
            do {
                for remaining in stride(from: 3, through: 1, by: -1) {
                    phase = .countdown(remaining)
                    try await sleep()
                    try validate(identity)
                }
                phase = .starting
                guard let source = session?.source else { throw CancellationError() }
                let format = try await source.prepare(target, frameRate: frameRate)
                try validate(identity)
                let workspace = try await RecordingFiles.workspace(in: folder)
                session?.workspace = workspace
                try validate(identity)
                let writer = try await makeWriter(workspace.appendingPathComponent("capture.mp4"), format)
                session?.writer = writer
                try validate(identity)
                try await source.start(writer: writer) { [weak self] error in
                    guard let self, self.operation == identity else { return }
                    self.lastError = error
                    self.recoveryTask = Task { [self] in
                        defer { recoveryTask = nil }
                        _ = await startTask?.result
                        guard operation == identity, phase == .recording || phase == .paused else { return }
                        do { _ = try await finish() } catch { lastError = error }
                    }
                }
                try validate(identity)
                phase = .recording
            } catch {
                await cleanSession(identity)
                if !(error is CancellationError) { lastError = error }
                throw error
            }
        }
        startTask = task
        do {
            try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
        } catch {
            if error is CancellationError, session?.identity == identity {
                cancel()
                await waitUntilIdle()
            }
            throw error
        }
    }

    func setPaused(_ paused: Bool) throws {
        guard phase == .recording || phase == .paused, let writer = session?.writer else {
            throw RecordingTarget.Failure.notRecording
        }
        writer.setPaused(paused, at: hostTime())
        phase = paused ? .paused : .recording
    }

    func finish() async throws -> URL {
        try Task.checkCancellation()
        guard phase == .recording || phase == .paused, let session,
            let writer = session.writer, let workspace = session.workspace else {
            throw RecordingTarget.Failure.notRecording
        }
        phase = .stopping
        let end = hostTime()
        writer.setPaused(true, at: end)
        let task = Task { [self] in
            defer { finishTask = nil }
            do {
                do { try await session.source.stop() } catch { lastError = error }
                try validate(session.identity)
                try await writer.finish(at: end)
                try validate(session.identity)
                let output = try await RecordingFiles.publish(
                    workspace: workspace, date: session.date, timeZone: session.timeZone)
                await cleanSession(session.identity)
                return output
            } catch {
                await cleanSession(session.identity)
                if !(error is CancellationError) { lastError = error }
                throw error
            }
        }
        finishTask = task
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func cancel() {
        operation = nil
        startTask?.cancel()
        finishTask?.cancel()
        session?.writer?.setPaused(true, at: hostTime())
        guard let session else { return }
        phase = .stopping
        guard startTask == nil, finishTask == nil, cleanupTask == nil else { return }
        cleanupTask = Task { [self] in
            await cleanSession(session.identity)
            cleanupTask = nil
        }
    }

    func waitUntilIdle() async {
        await shutdownTask?.value
        _ = await startTask?.result
        await recoveryTask?.value
        _ = await finishTask?.result
        await cleanupTask?.value
    }

    static func failureMessage(_ error: any Error) -> String {
        if let shared = CaptureFailure(error) { return shared.message }
        return switch error as? RecordingTarget.Failure {
        case .busy: String(localized: "A recording is already in progress.", table: "Notchcast")
        case .notRecording: String(localized: "No recording is in progress.", table: "Notchcast")
        case .noFrames: String(localized: "The recording contains no frames.", table: "Notchcast")
        case .invalidFolder, .writerFailed: String(localized: "Could not save the recording.", table: "Notchcast")
        default: String(localized: "Recording failed.", table: "Notchcast")
        }
    }

    private func validate(_ identity: UUID) throws {
        try Task.checkCancellation()
        guard enabled, operation == identity else { throw CancellationError() }
    }

    private func cleanSession(_ identity: UUID) async {
        guard let session, session.identity == identity else { return }
        if let error = await Self.dispose(session) { lastError = error }
        self.session = nil
        operation = nil
        phase = .idle
    }

    private static func dispose(_ session: Session) async -> (any Error)? {
        var failure: (any Error)?
        do { try await session.source.stop() } catch { failure = error }
        await session.writer?.cancel()
        if let workspace = session.workspace {
            do { try await RecordingFiles.discard(workspace) } catch { failure = error }
        }
        if let failure {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast", category: "Recording")
                .error("Recording cleanup failed: \(failure.localizedDescription, privacy: .public)")
        }
        return failure
    }

    isolated deinit {
        commandTask?.cancel()
        startTask?.cancel()
        finishTask?.cancel()
        cleanupTask?.cancel()
        recoveryTask?.cancel()
        if let session {
            Task { @MainActor in _ = await RecordingModule.dispose(session) }
        }
    }
}

extension RecordingTarget.Failure: CaptureFailureConvertible {
    var captureFailure: CaptureFailure? {
        switch self {
        case .permissionDenied: .permissionDenied
        case .disabled: .disabled
        case .invalidTarget, .targetUnavailable: .areaUnavailable
        case .busy, .writerFailed, .noFrames, .notRecording, .invalidFolder: nil
        }
    }
}
