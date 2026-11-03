import Darwin
import Foundation

nonisolated struct ProcessSampler: Sendable {
    private var previous: [ProcessReading.Identity: ProcessReading.Counter] = [:]

    mutating func sample(limit: Int = 5) -> ProcessReading {
        let current = Self.counters()
        defer { previous = Dictionary(current.map { ($0.identity, $0) }, uniquingKeysWith: { _, last in last }) }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return ProcessReading.ranked(current: current, previous: previous,
                                     timebaseNumerator: timebase.numer, timebaseDenominator: timebase.denom,
                                     limit: limit)
    }

    mutating func reset() { previous = [:] }

    private static func counters() -> [ProcessReading.Counter] {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.045
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: min(Int(estimate) + 128, 65_536))
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        var result: [ProcessReading.Counter] = []
        for pid in pids.prefix(min(Int(count), pids.count)) where pid > 0 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            if let counter = counter(pid) { result.append(counter) }
        }
        return result
    }

    private static func counter(_ pid: Int32) -> ProcessReading.Counter? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size) == size,
              info.pbsd.pbi_pid == UInt32(pid), info.pbsd.pbi_start_tvsec > 0 else { return nil }
        let total = info.ptinfo.pti_total_user.addingReportingOverflow(info.ptinfo.pti_total_system)
        guard !total.overflow else { return nil }
        let name = withUnsafeBytes(of: info.pbsd.pbi_name) {
            String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
        let command = withUnsafeBytes(of: info.pbsd.pbi_comm) {
            String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
        let identity = ProcessReading.Identity(pid: pid, startSeconds: info.pbsd.pbi_start_tvsec,
                                               startMicroseconds: info.pbsd.pbi_start_tvusec)
        return ProcessReading.Counter(identity: identity, name: name.isEmpty ? command : name,
                                      cpuTicks: total.partialValue, residentBytes: info.ptinfo.pti_resident_size,
                                      sampledAt: ProcessInfo.processInfo.systemUptime)
    }
}
