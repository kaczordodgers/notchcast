import Darwin
import Foundation

struct KatanaAmpLock {
    let path: String
    var timeout: Duration = .seconds(10)

    func acquire() async throws -> Int32? {
        try Task.checkCancellation()
        let descriptor = open(path, O_RDWR | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while true {
                try Task.checkCancellation()
                if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return descriptor }
                guard errno == EWOULDBLOCK || errno == EINTR else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                guard clock.now < deadline else { throw KatanaError.ampBusy }
                try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(100))))
            }
        } catch {
            close(descriptor)
            throw error
        }
    }

    func release(_ descriptor: Int32?) {
        guard let descriptor else { return }
        close(descriptor)
    }
}
