import Foundation
import Synchronization

final class SoloistOutput: Sendable {
    private struct Buffer {
        var data = Data()
        var discarding = false
    }

    private let buffer = Mutex(Buffer())
    private let scrub: SoloistLogScrub
    private let log: @Sendable (String) -> Void

    init(arguments: [String], log: @escaping @Sendable (String) -> Void) {
        scrub = SoloistLogScrub(arguments: arguments)
        self.log = log
    }

    func consume(_ data: Data) {
        buffer.withLock { buffer in
            for byte in data {
                if byte == 10 {
                    emit(&buffer)
                } else if !buffer.discarding {
                    if buffer.data.count >= 65_536 {
                        buffer.data.removeAll(keepingCapacity: false)
                        buffer.discarding = true
                    } else { buffer.data.append(byte) }
                }
            }
        }
    }

    func finish() {
        buffer.withLock { emit(&$0) }
    }

    private func emit(_ buffer: inout Buffer) {
        if !buffer.discarding, !buffer.data.isEmpty, let text = String(data: buffer.data, encoding: .utf8) {
            log("soloist: " + scrub.scrub(text))
        }
        buffer.data.removeAll(keepingCapacity: true)
        buffer.discarding = false
    }
}
