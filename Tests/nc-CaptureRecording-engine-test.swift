// notchcast-sources: -target arm64-apple-macos26.0 Tinycast/Features/CaptureRecording/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingFiles.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingWriting.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingWriter.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingSource.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingStreamTap.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/ScreenRecordingSource.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingModule.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-kit: core host
import AVFoundation
import Foundation

enum DialogTone { case danger, neutral, success }
import Synchronization

@main
struct RecordingTests {
    @MainActor
    static func main() async throws {
        try timelineAndNaming()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try await lifecycle(in: root)
        try await cancellation(in: root)
        try await lateResults(in: root)
        try await writer(in: root)
        try await pacedWriter(in: root)
        print("PASS recording timeline, naming, preferences, switch lifecycle, cancellation and H.264/AAC writer")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    private static func timelineAndNaming() throws {
        let date = Date(timeIntervalSince1970: 0)
        expect(date.captureFileName(kind: "Recording", extension: "mp4", timeZone: .gmt) ==
            "Recording 1970-01-01 at 00.00.00.mp4", "stable POSIX filename")
        expect(date.captureFileName(
            kind: "Recording", extension: "mp4", timeZone: .gmt, collision: 2) ==
            "Recording 1970-01-01 at 00.00.00 (2).mp4", "collision suffix")
        expect(!RecordingTarget.isValid(CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)), "reject infinite rect")
        expect(!RecordingTarget.isValid(CGRect(x: 0, y: 0, width: -1, height: 10)), "reject negative rect")
        var timeline = RecordingTimeline()
        expect(timeline.sampleTime(at: 10, duration: 0) == nil, "no sample before origin")
        timeline.begin(at: 10)
        timeline.setPaused(true, at: 12)
        timeline.setPaused(true, at: 13)
        expect(timeline.elapsed(at: 15) == 2, "repeated pause keeps original edge")
        expect(timeline.sampleTime(at: 11.99, duration: 0.02) == nil, "audio spanning pause is rejected")
        timeline.setPaused(false, at: 17)
        expect(timeline.sampleTime(at: 14, duration: 0.1) == nil, "late paused sample is rejected")
        expect(timeline.sampleTime(at: 17, duration: 0.1) == 2, "both tracks remove pause duration")
        timeline.setPaused(true, at: 20)
        timeline.setPaused(false, at: 22)
        expect(timeline.elapsed(at: 23) == 6, "multiple pauses")
    }

    @MainActor
    private static func lifecycle(in root: URL) async throws {
        let suite = "recording-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.recording, false)
        let source = FakeSource()
        let writer = FakeWriter()
        let ticks = Mutex(0)
        let module = RecordingModule(
            defaults: defaults, defaultFolder: root, makeSource: { source },
            makeWriter: { url, _ in try Data("movie".utf8).write(to: url); return writer },
            sleep: { ticks.withLock { $0 += 1 } },
            now: { Date(timeIntervalSince1970: 0) }, timeZone: { .gmt },
            hostTime: { CMTime(seconds: 12, preferredTimescale: 600) })
        let controller = NotchcastModuleController([.init(requires: [.recording], module: module)], preferences: preferences)
        controller.run()
        expect(!module.enabled, "switch starts disabled")
        do { try await module.record(.display(1)); preconditionFailure("disabled start")
        } catch RecordingTarget.Failure.disabled { }
        preferences.set(.recording, true)
        await settle { module.enabled }
        expect(module.frameRate == 60, "default 60 fps")
        module.frameRate = 30
        module.folder = root
        try await module.record(.display(1))
        expect(ticks.withLock { $0 } == 3 && source.prepares == 1 && source.starts == 1, "countdown before capture")
        expect(source.frameRate == 30 && module.phase == .recording, "frame rate and recording state")
        do { try await module.record(.window(2)); preconditionFailure("concurrent start")
        } catch RecordingTarget.Failure.busy { }
        try module.setPaused(true)
        expect(module.phase == .paused, "pause state")
        try module.setPaused(false)
        let occupied = root.appendingPathComponent("Recording 1970-01-01 at 00.00.00.mp4")
        try Data("keep".utf8).write(to: occupied)
        let output = try await module.finish()
        expect(output.lastPathComponent == "Recording 1970-01-01 at 00.00.00 (1).mp4", "publish skips occupied name")
        let original = try Data(contentsOf: occupied)
        let movie = try Data(contentsOf: output)
        expect(original == Data("keep".utf8), "existing movie preserved")
        expect(movie == Data("movie".utf8), "completed movie published")
        expect(module.phase == .idle && writer.finishes.withLock { $0 } == 1, "finish returns idle")
        try await module.record(.window(2))
        preferences.set(.recording, false)
        await settle { !module.enabled }
        await module.waitUntilIdle()
        expect(module.phase == .idle && source.stops >= 2, "switch stops active source")
        expect(writer.cancelled.withLock { $0 }, "switch cancels writer")
        let restored = RecordingModule(defaults: defaults, defaultFolder: root, makeSource: { source })
        expect(restored.frameRate == 30 && restored.folder == root, "preferences use injected suite")
        restored.frameRate = 999
        expect(restored.frameRate == 60, "unsupported frame rate resets to 60")
    }

    @MainActor
    private static func cancellation(in root: URL) async throws {
        let suite = "recording-cancel-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = FakeSource()
        let module = RecordingModule(
            defaults: defaults, defaultFolder: root, makeSource: { source },
            sleep: { try await Task.sleep(for: .seconds(60)) })
        module.start()
        let task = Task { try await module.record(.area(CGRect(x: -100, y: 0, width: 10, height: 10))) }
        await settle { module.phase == .countdown(3) }
        module.stop()
        do { try await task.value; preconditionFailure("cancelled countdown") } catch is CancellationError { }
        expect(source.prepares == 0 && source.starts == 0 && module.phase == .idle, "cancel countdown before capture")
        module.start()
        let caller = Task { try await module.record(.display(1)) }
        await settle { module.phase == .countdown(3) }
        caller.cancel()
        do { try await caller.value; preconditionFailure("caller cancellation") } catch is CancellationError { }
        expect(module.phase == .idle, "caller owns countdown cancellation")
        var requests = 0
        let denied = ScreenRecordingSource(hasAccess: { false }, requestAccess: { requests += 1; return false })
        do {
            _ = try await denied.prepare(.display(1), frameRate: 60)
            preconditionFailure("permission denial")
        } catch RecordingTarget.Failure.permissionDenied { }
        expect(requests == 1, "injected grant denial never reads the screen")
    }

    @MainActor
    private static func lateResults(in root: URL) async throws {
        let suite = "recording-late-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = FakeSource()
        source.holdPreparation = true
        let module = RecordingModule(
            defaults: defaults, defaultFolder: root, makeSource: { source },
            makeWriter: { url, _ in try Data("movie".utf8).write(to: url); return FakeWriter() },
            sleep: { })
        module.start()
        let preparing = Task { try await module.record(.display(1)) }
        await settle { source.pendingPreparation != nil }
        module.cancel()
        source.pendingPreparation?.resume()
        source.pendingPreparation = nil
        do { try await preparing.value; preconditionFailure("late preparation") } catch is CancellationError { }
        expect(source.starts == 0 && module.phase == .idle, "cancel rejects late content snapshot")
        source.holdPreparation = false
        source.holdStart = true
        let starting = Task { try await module.record(.window(2)) }
        await settle { source.pendingStart != nil }
        module.stop()
        source.pendingStart?.resume()
        source.pendingStart = nil
        do { try await starting.value; preconditionFailure("late stream start") } catch is CancellationError { }
        expect(module.phase == .idle && source.stops >= 2, "late native start is stopped before idle")
        let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        expect(!contents.contains { $0.lastPathComponent.hasPrefix(".recording-") }, "cancel removes temporary workspace")
        source.holdStart = false
        source.startFailure = RecordingTarget.Failure.targetUnavailable
        module.start()
        do {
            try await module.record(.display(1))
            preconditionFailure("start failure")
        } catch RecordingTarget.Failure.targetUnavailable { }
        expect(module.phase == .idle && module.lastError != nil, "native errors surface and release resources")
        source.startFailure = nil
        let beforeStop = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let previousCount = beforeStop.filter { $0.pathExtension == "mp4" }.count
        source.stopFailure = RecordingTarget.Failure.targetUnavailable
        try await module.record(.display(1))
        source.onFailure?(RecordingTarget.Failure.targetUnavailable)
        await module.waitUntilIdle()
        expect(module.phase == .idle && module.lastError != nil, "stream stop finalizes recording")
        let saved = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let savedCount = saved.filter { $0.pathExtension == "mp4" }.count
        expect(savedCount == previousCount + 1, "closed window preserves the take")
        source.stopFailure = nil
        let failedWriter = FakeWriter(failFinish: true)
        let failedModule = RecordingModule(
            defaults: defaults, defaultFolder: root, makeSource: { source },
            makeWriter: { url, _ in try Data("broken".utf8).write(to: url); return failedWriter }, sleep: { })
        failedModule.start()
        try await failedModule.record(.display(1))
        source.onFailure?(RecordingTarget.Failure.writerFailed)
        await failedModule.waitUntilIdle()
        let afterFailure = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        expect(afterFailure.filter { $0.pathExtension == "mp4" }.count == savedCount, "writer failure discards take")
        expect(failedModule.phase == .idle && failedModule.lastError != nil, "writer failure releases session")
        let blockedWriter = FakeWriter(holdFinish: true)
        let finishingModule = RecordingModule(
            defaults: defaults, defaultFolder: root, makeSource: { FakeSource() },
            makeWriter: { url, _ in try Data("discard".utf8).write(to: url); return blockedWriter }, sleep: { })
        finishingModule.start()
        try await finishingModule.record(.display(1))
        let finishing = Task { try await finishingModule.finish() }
        await settle { blockedWriter.pendingFinish.withLock { $0 != nil } }
        finishingModule.cancel()
        blockedWriter.pendingFinish.withLock { continuation in
            continuation?.resume()
            continuation = nil
        }
        do { _ = try await finishing.value; preconditionFailure("late writer finish") } catch is CancellationError { }
        expect(finishingModule.phase == .idle, "cancel rejects late writer finalization")
        let afterFinish = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        expect(!afterFinish.contains { $0.lastPathComponent.hasPrefix(".recording-") }, "finalization cancel cleans output")
    }

    @MainActor
    private static func settle(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("main actor did not settle")
    }

    @MainActor
    private static func writer(in root: URL) async throws {
        let suite = "recording-writer-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = FakeSource()
        source.origin = CMTime(seconds: 10, preferredTimescale: 600)
        var currentTime = 10.5
        let module = RecordingModule(
            defaults: defaults, defaultFolder: root, makeSource: { source }, sleep: { },
            now: { Date(timeIntervalSince1970: 86_400) }, timeZone: { .gmt },
            hostTime: { CMTime(seconds: currentTime, preferredTimescale: 600) })
        module.start()
        try await module.record(.area(CGRect(x: -64, y: 0, width: 64, height: 64)))
        guard let writer = source.outputWriter else { preconditionFailure("writer injected into source") }
        for frame in 0..<30 {
            let time = 10 + Double(frame) / 60
            try writer.append(video(at: time), track: .video)
            try writer.append(audio(at: time), track: .systemAudio)
        }
        try module.setPaused(true)
        try writer.append(video(at: 11), track: .video)
        currentTime = 12.5
        try module.setPaused(false)
        for frame in 0..<30 {
            let time = 12.5 + Double(frame) / 60
            try writer.append(video(at: time), track: .video)
            try writer.append(audio(at: time), track: .systemAudio)
        }
        currentTime = 13.5
        let url = try await module.finish()
        expect(module.phase == .idle, "synthetic recording completes through module")
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        expect(abs(duration.seconds - 1.5) < 0.1, "pause removed and still tail preserved: \(duration.seconds)")
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        expect(video.count == 1 && audio.count == 1, "video and system audio tracks")
        let formats = try await video[0].load(.formatDescriptions)
        expect(CMFormatDescriptionGetMediaSubType(formats[0]) == kCMVideoCodecType_H264, "H.264 video")
        let audioFormats = try await audio[0].load(.formatDescriptions)
        expect(CMFormatDescriptionGetMediaSubType(audioFormats[0]) == kAudioFormatMPEG4AAC, "AAC system audio")
        let empty = try await RecordingWriter.create(
            url: root.appendingPathComponent("empty.mp4"), format: RecordingFormat(width: 64, height: 64, frameRate: 30))
        empty.begin(at: .zero)
        do { try await empty.finish(at: CMTime(seconds: 1, preferredTimescale: 600)); preconditionFailure("empty output")
        } catch RecordingTarget.Failure.noFrames { }
    }

    private static func video(
        at seconds: Double, width: Int = 64, height: Int = 64,
        duration: CMTime = CMTime(value: 1, timescale: 60)
    ) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == noErr)
        let image = pixel!
        CVPixelBufferLockBaseAddress(image, [])
        memset(CVPixelBufferGetBaseAddress(image), 0, CVPixelBufferGetDataSize(image))
        CVPixelBufferUnlockBaseAddress(image, [])
        var description: CMVideoFormatDescription?
        precondition(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &description) == noErr)
        var timing = CMSampleTimingInfo(duration: duration,
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        precondition(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
            formatDescription: description!, sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
        return sample!
    }

    private static func pacedWriter(in root: URL) async throws {
        let url = root.appendingPathComponent("paced.mp4")
        let writer = try RecordingWriter(url: url, format: RecordingFormat(width: 1280, height: 720, frameRate: 30))
        writer.begin(at: .zero)
        for frame in 0..<30 {
            try writer.append(video(at: Double(frame) / 10, width: 1280, height: 720, duration: .invalid), track: .video)
            try writer.append(audio(at: Double(frame) / 10), track: .systemAudio)
            try await Task.sleep(for: .milliseconds(100))
        }
        try await writer.finish(at: CMTime(seconds: 3, preferredTimescale: 600))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var frames = 0
        while output.copyNextSampleBuffer() != nil { frames += 1 }
        expect(frames >= 30, "paced live capture retains every frame: \(frames)")
        print("PASS paced 1280x720 capture retains \(frames) frames and finishes")
        for attempt in 0..<10 {
            let finishingTask = Mutex<Task<Void, any Error>?>(nil)
            let beganFinalizing = Mutex(false)
            let cancelling = try RecordingWriter(url: root.appendingPathComponent("cancel-\(attempt).mp4"),
                format: RecordingFormat(width: 1280, height: 720, frameRate: 30), onFinalizing: {
                    beganFinalizing.withLock { $0 = true }
                    let task = finishingTask.withLock { $0 }
                    task?.cancel()
                })
            cancelling.begin(at: .zero)
            for frame in 0..<30 {
                try cancelling.append(video(at: Double(frame) / 30, width: 1280, height: 720), track: .video)
            }
            let finish = finishingTask.withLock { task in
                let finish = Task { try await cancelling.finish(at: CMTime(seconds: 3, preferredTimescale: 600)) }
                task = finish
                return finish
            }
            do {
                try await finish.value
                preconditionFailure("cancelled finalization succeeded")
            } catch is CancellationError { }
            expect(beganFinalizing.withLock { $0 }, "cancel occurs after native finalization begins")
        }
        print("PASS cancellation releases native writer finish")
    }

    private static func audio(at seconds: Double) throws -> CMSampleBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 800)!
        buffer.frameLength = 800
        for channel in 0..<2 { memset(buffer.floatChannelData![channel], 0, 800 * MemoryLayout<Float>.size) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        precondition(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription, sampleCount: 800,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0,
            sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
        precondition(CMSampleBufferSetDataBufferFromAudioBufferList(sample!, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList) == noErr)
        precondition(CMSampleBufferSetDataReady(sample!) == noErr)
        return sample!
    }

    @MainActor
    private final class FakeSource: RecordingSource {
        var prepares = 0
        var starts = 0
        var stops = 0
        var frameRate = 0
        var origin = CMTime.zero
        var outputWriter: (any RecordingWriting)?
        var holdPreparation = false
        var holdStart = false
        var startFailure: (any Error)?
        var stopFailure: (any Error)?
        var pendingPreparation: CheckedContinuation<Void, Never>?
        var pendingStart: CheckedContinuation<Void, Never>?
        var onFailure: (@MainActor (any Error) -> Void)?
        func prepare(_ target: RecordingTarget, frameRate: Int) async throws -> RecordingFormat {
            prepares += 1
            self.frameRate = frameRate
            if holdPreparation { await withCheckedContinuation { pendingPreparation = $0 } }
            return RecordingFormat(width: 64, height: 64, frameRate: frameRate)
        }
        func start(writer: any RecordingWriting, onFailure: @escaping @MainActor (any Error) -> Void) async throws {
            starts += 1
            self.onFailure = onFailure
            outputWriter = writer
            writer.begin(at: origin)
            if holdStart { await withCheckedContinuation { pendingStart = $0 } }
            if let startFailure { throw startFailure }
        }
        func stop() async throws {
            stops += 1
            outputWriter = nil
            if let stopFailure { throw stopFailure }
        }
    }

    private final class FakeWriter: RecordingWriting {
        let cancelled = Mutex(false)
        let finishes = Mutex(0)
        let pendingFinish = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let holdFinish: Bool
        let failFinish: Bool
        init(holdFinish: Bool = false, failFinish: Bool = false) {
            self.holdFinish = holdFinish
            self.failFinish = failFinish
        }
        func begin(at time: CMTime) { }
        func append(_ sample: CMSampleBuffer, track: RecordingFormat.Track) throws { }
        func setPaused(_ paused: Bool, at time: CMTime) { }
        func finish(at time: CMTime) async throws {
            finishes.withLock { $0 += 1 }
            if failFinish { throw RecordingTarget.Failure.writerFailed }
            if holdFinish { await withCheckedContinuation { continuation in pendingFinish.withLock { $0 = continuation } } }
        }
        func cancel() async { cancelled.withLock { $0 = true } }
    }
}
