import Foundation
import Darwin

nonisolated struct KillProcessService: Sendable {
    enum Signal: Int32, Sendable { case terminate = 15, force = 9 }
    enum Failure: Error { case protectedProcess, staleIdentity }

    func read() -> [KillProcessEntry] {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(bytes) + 256)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard count > 0 else { return [] }
        return pids.prefix(min(Int(count), pids.count)).compactMap { read(pid: $0) }
    }

    func read(pid: Int32) -> KillProcessEntry? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_pid == UInt32(pid), info.pbi_status != UInt32(SZOMB) else { return nil }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        guard let path = String(bytes: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
                                encoding: .utf8) else { return nil }
        return KillProcessEntry(pid: pid, parentPID: Int32(info.pbi_ppid), uid: info.pbi_uid,
                                startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec,
                                path: path)
    }

    func apply(targets: [KillProcessEntry], signal: Signal, uid: UInt32, ownPID: Int32,
               lookup: (Int32) throws -> KillProcessEntry?,
               run: (Int32, Signal) throws -> Void) throws {
        for target in targets {
            guard target.canStop(uid: uid, ownPID: ownPID) else { throw Failure.protectedProcess }
            guard let current = try lookup(target.pid), target.sameIdentity(as: current) else {
                throw Failure.staleIdentity
            }
            guard current.canStop(uid: uid, ownPID: ownPID) else { throw Failure.protectedProcess }
        }
        for target in targets {
            guard let current = try lookup(target.pid), target.sameIdentity(as: current) else {
                throw Failure.staleIdentity
            }
            guard current.canStop(uid: uid, ownPID: ownPID) else { throw Failure.protectedProcess }
            try run(target.pid, signal)
        }
    }
}
