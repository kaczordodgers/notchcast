import AVFoundation
import AudioToolbox
import CoreMedia
import Synchronization

@MainActor
final class DictationCapture {
    enum Failure: LocalizedError {
        case microphoneUnavailable
        case microphoneDenied
        case captureUnavailable
        case coreAudioUnresponsive

        var errorDescription: String? {
            switch self {
            case .microphoneUnavailable: String(localized: "No microphone is available.")
            case .microphoneDenied:
                String(localized: "Allow Tinycast to use the microphone in System Settings.")
            case .captureUnavailable: String(localized: "Couldn't start recording from this microphone.")
            case .coreAudioUnresponsive:
                String(localized: "Core Audio isn't responding (coreaudiod); restart it or your Mac.")
            }
        }
    }

    static var microphones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
    }

    var onLevels: (([Float]) -> Void)?
    var onLimit: (() -> Void)?

    private(set) var isBluetooth = false
    private var session: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?
    private var collector: AudioCollector?

    func start(microphoneID: String?) async throws {
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        let granted: Bool
        if permission == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            granted = permission == .authorized
        }
        guard granted else { throw Failure.microphoneDenied }
        let device =
            microphoneID.map { id in Self.microphones.first { $0.uniqueID == id } }
            ?? AVCaptureDevice.default(for: .audio)
        guard let device else { throw Failure.microphoneUnavailable }
        isBluetooth = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE]
            .contains(UInt32(bitPattern: device.transportType))
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw Failure.captureUnavailable
        }

        let capture = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: DictationWire.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
            throw Failure.captureUnavailable
        }
        capture.addInput(input)
        capture.addOutput(output)
        let collector = try AudioCollector(
            onLevels: { [weak self] levels in
                Task { @MainActor [weak self] in self?.onLevels?(levels) }
            },
            onLimit: { [weak self] in
                Task { @MainActor [weak self] in self?.onLimit?() }
            })
        output.setSampleBufferDelegate(collector, queue: collector.queue)
        self.session = capture
        self.output = output
        self.collector = collector
        let box = CaptureSessionBox(capture)
        do {
            try await Self.startBounded(
                start: { box.session.startRunning(); return box.session.isRunning },
                stop: { box.session.stopRunning() })
        } catch {
            self.session = nil
            self.output = nil
            self.collector = nil
            throw error
        }
        guard capture.isRunning else {
            _ = await stop()
            throw Failure.captureUnavailable
        }
    }

    func stop() async -> [Float] {
        guard let session else { return [] }
        self.session = nil
        let box = CaptureSessionBox(session)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                box.session.stopRunning()
                continuation.resume()
            }
        }
        output?.setSampleBufferDelegate(nil, queue: nil)
        output = nil
        let samples = collector?.finish() ?? []
        collector = nil
        return samples
    }

    func snapshot() -> [Float] {
        guard session != nil else { return [] }
        return collector?.snapshot() ?? []
    }
}

extension DictationCapture {
    nonisolated static func startBounded(
        timeout: Duration = .seconds(5),
        start: @escaping @Sendable () -> Bool, stop: @escaping @Sendable () -> Void
    ) async throws {
        let attempt = StartAttempt()
        let running = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard attempt.install(continuation) else { return }
                let deadline = Task {
                    do { try await Task.sleep(for: timeout) } catch { return }
                    attempt.complete(.failure(Failure.coreAudioUnresponsive))
                }
                attempt.setDeadline(deadline)
                // A blocked driver cannot be cancelled; late success closes its own session.
                DispatchQueue.global().async {
                    let running = start()
                    if !attempt.complete(.success(running)), running { stop() }
                }
            }
        } onCancel: {
            attempt.complete(.failure(CancellationError()))
        }
        guard running else { throw Failure.captureUnavailable }
    }

    private final class StartAttempt: Sendable {
        private struct State {
            var continuation: CheckedContinuation<Bool, any Error>?
            var result: Result<Bool, any Error>?
            var deadline: Task<Void, Never>?
        }

        private let state = Mutex(State())

        func install(_ continuation: CheckedContinuation<Bool, any Error>) -> Bool {
            let result = state.withLock { state -> Result<Bool, any Error>? in
                if let result = state.result { return result }
                state.continuation = continuation
                return nil
            }
            if let result { continuation.resume(with: result) }
            return result == nil
        }

        func setDeadline(_ deadline: Task<Void, Never>) {
            let completed = state.withLock { state in
                guard state.result == nil else { return true }
                state.deadline = deadline
                return false
            }
            if completed { deadline.cancel() }
        }

        @discardableResult
        func complete(_ result: Result<Bool, any Error>) -> Bool {
            let completion = state.withLock { state -> (Bool, CheckedContinuation<Bool, any Error>?) in
                guard state.result == nil else { return (false, nil) }
                state.result = result
                let continuation = state.continuation
                state.continuation = nil
                state.deadline?.cancel()
                state.deadline = nil
                return (true, continuation)
            }
            completion.1?.resume(with: result)
            return completion.0
        }
    }
}

// Configuration stays on main; only start/stop run off-main, in sequence.
private struct CaptureSessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

// Sample buffers and mutable state are confined to the delegate queue, including finish().
private final class AudioCollector: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    let queue = DispatchQueue(label: "com.tinycast.dictation.audio")
    private var samples: [Float] = []
    private var displayedLevels: [Float]
    private let spectrum: DictationSpectrum
    private var waveformStartIndex = 0
    private var lastLevelUpdate: TimeInterval = 0
    private var reachedLimit = false
    private let onLevels: @Sendable ([Float]) -> Void
    private let onLimit: @Sendable () -> Void

    init(onLevels: @escaping @Sendable ([Float]) -> Void, onLimit: @escaping @Sendable () -> Void) throws {
        spectrum = try DictationSpectrum()
        displayedLevels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        self.onLevels = onLevels
        self.onLimit = onLimit
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        var blockBuffer: CMBlockBuffer?
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let data = bufferList.mBuffers.mData else { return }
        let count = Int(bufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0, samples.count < DictationWire.maximumSamples else { return }
        let floats = data.assumingMemoryBound(to: Float.self)
        let accepted = min(count, DictationWire.maximumSamples - samples.count)
        samples.append(contentsOf: UnsafeBufferPointer(start: floats, count: accepted))
        if samples.count == DictationWire.maximumSamples, !reachedLimit {
            reachedLimit = true
            onLimit()
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelUpdate >= 0.05 else { return }
        lastLevelUpdate = now
        let levels = spectrum.levels(for: samples[waveformStartIndex...])
        waveformStartIndex = samples.count
        for index in levels.indices {
            let response: Float = levels[index] > displayedLevels[index] ? 0.6 : 0.25
            displayedLevels[index] += (levels[index] - displayedLevels[index]) * response
        }
        onLevels(displayedLevels)
    }

    func finish() -> [Float] { queue.sync { samples } }

    func snapshot() -> [Float] { queue.sync { samples } }
}
