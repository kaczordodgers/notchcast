import Foundation

extension FileHandle {
    /// Reads on the handle's own dispatch source, so a waiting reader holds no cooperative-pool thread.
    func chunks() -> AsyncStream<Data> {
        AsyncStream { continuation in
            continuation.onTermination = { [self] _ in readabilityHandler = nil }
            readabilityHandler = { handle in
                let chunk = handle.availableData
                guard chunk.isEmpty else { continuation.yield(chunk); return }
                handle.readabilityHandler = nil
                continuation.finish()
            }
        }
    }
}
