import Darwin
import Foundation

struct SoloistPeer: Equatable, Sendable {
    let pid: Int32
    let path: String
}

@MainActor
protocol SoloistProcessList: AnyObject {
    func soloists() -> [SoloistPeer]
    func watchExit(of pid: Int32, _ onExit: @escaping @MainActor () -> Void) -> SoloistCancellation
    func stop(_ peer: SoloistPeer)
}

@MainActor
final class LiveSoloistProcessList: SoloistProcessList {
    func soloists() -> [SoloistPeer] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return pids.prefix(min(Int(filled), pids.count)).compactMap { pid in
            guard pid > 0, let path = Self.path(of: pid), URL(filePath: path).lastPathComponent == "soloist" else {
                return nil
            }
            return SoloistPeer(pid: pid, path: path)
        }
    }

    func watchExit(of pid: Int32, _ onExit: @escaping @MainActor () -> Void) -> SoloistCancellation {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        let work = Task { @MainActor in
            await withCheckedContinuation { continuation in
                source.setCancelHandler { continuation.resume() }
                source.setEventHandler { source.cancel() }
                source.resume()
                if kill(pid, 0) != 0, errno == ESRCH { source.cancel() }
            }
            guard !Task.isCancelled else { return }
            onExit()
        }
        return SoloistCancellation {
            work.cancel()
            source.cancel()
        }
    }

    func stop(_ peer: SoloistPeer) {
        guard Self.path(of: peer.pid) == peer.path, kill(peer.pid, SIGTERM) == 0 else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if Self.path(of: peer.pid) == peer.path { kill(peer.pid, SIGKILL) }
        }
    }

    private static func path(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(bytes: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }
}
