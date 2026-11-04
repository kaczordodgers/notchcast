import ScreenCaptureKit
import Synchronization

final class RecordingStreamTap: NSObject, SCStreamOutput, SCStreamDelegate, Sendable {
    private let writer: any RecordingWriting
    private let ended = Mutex(false)
    private let onFailure: @Sendable (any Error) -> Void

    init(writer: any RecordingWriting, onFailure: @escaping @Sendable (any Error) -> Void) {
        self.writer = writer
        self.onFailure = onFailure
    }

    func silence() { ended.withLock { $0 = true } }

    private func fail(_ error: any Error) {
        let first = ended.withLock { ended in
            guard !ended else { return false }
            ended = true
            return true
        }
        if first { onFailure(error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let track: RecordingFormat.Track
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
                let status = attachments.first?[.status] as? Int,
                status == SCFrameStatus.complete.rawValue else { return }
            track = .video
        case .audio: track = .systemAudio
        default: return
        }
        do { try writer.append(sampleBuffer, track: track) } catch { fail(error) }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) { fail(error) }
}
