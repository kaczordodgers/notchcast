import AVFoundation
import CoreMedia
import Synchronization

final class RecordingWriter: RecordingWriting {
    // AVAssetWriter cancellation must be callable while its asynchronous finish is pending.
    private struct FinishingWriter: @unchecked Sendable {
        let writer: AVAssetWriter
        var continuation: CheckedContinuation<Bool, Never>?
        var cancelled = false
    }

    private struct State {
        let writer: AVAssetWriter
        let video: AVAssetWriterInput.SampleBufferReceiver
        let audio: AVAssetWriterInput.SampleBufferReceiver
        let frameRate: Int
        var timeline = RecordingTimeline()
        var lastVideo: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>?
        var lastVideoTime = CMTime.invalid
        var lastAudioTime = CMTime.invalid
        var failure: (any Error)?
    }

    private let state: Mutex<State?>
    private let finishingWriter = Mutex<FinishingWriter?>(nil)
    private let onFinalizing: (@Sendable () -> Void)?

    init(url: URL, format: RecordingFormat, onFinalizing: (@Sendable () -> Void)? = nil) throws {
        self.onFinalizing = onFinalizing
        guard (2...16_384).contains(format.width), (2...16_384).contains(format.height),
            format.width.isMultiple(of: 2), format.height.isMultiple(of: 2),
            format.frameRate == 30 || format.frameRate == 60 else { throw RecordingTarget.Failure.invalidTarget }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: format.width,
            AVVideoHeightKey: format.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: format.frameRate,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ])
        video.expectsMediaDataInRealTime = true
        audio.expectsMediaDataInRealTime = true
        guard writer.canAdd(video), writer.canAdd(audio) else { throw RecordingTarget.Failure.writerFailed }
        let videoReceiver = writer.inputReceiver(for: video)
        let audioReceiver = writer.inputReceiver(for: audio)
        try writer.start()
        state = Mutex(State(writer: writer, video: videoReceiver, audio: audioReceiver, frameRate: format.frameRate))
    }

    @concurrent
    static func create(url: URL, format: RecordingFormat) async throws -> any RecordingWriting {
        try Task.checkCancellation()
        return try RecordingWriter(url: url, format: format)
    }

    func begin(at time: CMTime) {
        state.withLock { storage in
            guard var state = storage, state.timeline.origin == nil, time.isNumeric else { return }
            state.timeline.begin(at: time.seconds)
            state.writer.startSession(atSourceTime: .zero)
            storage = state
        }
    }

    func append(_ sample: CMSampleBuffer, track: RecordingFormat.Track) throws {
        guard CMSampleBufferDataIsReady(sample) else { return }
        let ready = try Self.readyCopy(sample)
        try state.withLock { storage in
            guard var state = storage else { return }
            defer { storage = state }
            if let failure = state.failure { throw failure }
            let time = ready.presentationTimeStamp
            let duration = ready.duration
            guard let mapped = state.timeline.sampleTime(at: time.seconds, duration: duration.seconds) else { return }
            let outputTime = CMTime(seconds: mapped, preferredTimescale: 600_000_000)
            let previous = track == .video ? state.lastVideoTime : state.lastAudioTime
            guard !previous.isNumeric || outputTime > previous else { return }
            do {
                let shifted = try Self.retime(ready, to: outputTime)
                let receiver = track == .video ? state.video : state.audio
                guard try receiver.appendImmediately(shifted) else { return }
                if track == .video {
                    state.lastVideo = ready
                    state.lastVideoTime = outputTime
                } else {
                    state.lastAudioTime = outputTime
                }
            } catch {
                state.failure = error
                throw error
            }
        }
    }

    func setPaused(_ paused: Bool, at time: CMTime) {
        state.withLock { storage in
            guard var state = storage else { return }
            state.timeline.setPaused(paused, at: time.seconds)
            storage = state
        }
    }

    @concurrent
    func finish(at time: CMTime) async throws {
        guard var finishing = takeState() else { throw CancellationError() }
        finishingWriter.withLock { $0 = FinishingWriter(writer: finishing.writer) }
        defer { finishingWriter.withLock { $0 = nil } }
        do {
            try Task.checkCancellation()
            guard let lastVideo = finishing.lastVideo, finishing.failure == nil else {
                throw finishing.failure ?? RecordingTarget.Failure.noFrames
            }
            let end = CMTime(seconds: finishing.timeline.elapsed(at: time.seconds), preferredTimescale: 600_000_000)
            let tail = end - CMTime(value: 1, timescale: CMTimeScale(finishing.frameRate))
            if tail > finishing.lastVideoTime {
                let sample = try Self.retime(lastVideo, to: tail)
                for _ in 0..<50 {
                    try Task.checkCancellation()
                    if try finishing.video.appendImmediately(sample) { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            try Task.checkCancellation()
            finishing.lastVideo = nil
            let completed = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    finishingWriter.withLock { handle in
                        guard let current = handle, !current.cancelled else {
                            continuation.resume(returning: false)
                            return
                        }
                        guard current.writer.status == .writing else {
                            continuation.resume(returning: true)
                            return
                        }
                        handle?.continuation = continuation
                        current.writer.endSession(atSourceTime: end)
                        finishing.video.finish()
                        finishing.audio.finish()
                        current.writer.finishWriting {
                            let pending = self.finishingWriter.withLock { handle in
                                let pending = handle?.continuation
                                handle?.continuation = nil
                                return pending
                            }
                            pending?.resume(returning: true)
                        }
                    }
                    onFinalizing?()
                }
            } onCancel: {
                self.cancelFinishing()
            }
            guard completed else { throw CancellationError() }
            try Task.checkCancellation()
            guard finishing.writer.status == .completed else {
                throw finishing.writer.error ?? RecordingTarget.Failure.writerFailed
            }
        } catch {
            finishing.writer.cancelWriting()
            throw error
        }
    }

    @concurrent
    func cancel() async {
        takeState()?.writer.cancelWriting()
        cancelFinishing()
    }

    private func cancelFinishing() {
        let cancelled = finishingWriter.withLock { handle in
            handle?.cancelled = true
            let cancelled = handle
            handle?.continuation = nil
            return cancelled
        }
        cancelled?.continuation?.resume(returning: false)
        cancelled?.writer.cancelWriting()
    }

    private func takeState() -> sending State? {
        state.withLock {
            let result = $0
            $0 = nil
            return result
        }
    }

    private static func retime(
        _ sample: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>, to time: CMTime
    ) throws -> CMReadySampleBuffer<CMSampleBuffer.DynamicContent> {
        var timing = try sample.withUnsafeSampleBuffer { try $0.sampleTimingInfos() }
        let shift = sample.presentationTimeStamp - time
        for index in timing.indices {
            timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, shift)
            if timing[index].decodeTimeStamp.isNumeric {
                timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, shift)
            }
        }
        return try sample.withUnsafeSampleBuffer { try readyCopy($0, timing: timing) }
    }

    private static func readyCopy(
        _ sample: CMSampleBuffer, timing: [CMSampleTimingInfo]? = nil
    ) throws -> CMReadySampleBuffer<CMSampleBuffer.DynamicContent> {
        // Only the copied header is mutable; capture payloads stay read-only while retained.
        nonisolated(unsafe) let copy = try timing.map { try CMSampleBuffer(copying: sample, withNewTiming: $0) }
            ?? CMSampleBuffer(copying: sample)
        return CMReadySampleBuffer(unsafeBuffer: copy)
    }
}
