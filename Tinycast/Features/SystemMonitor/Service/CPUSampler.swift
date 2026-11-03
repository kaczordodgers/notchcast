import Darwin
import Foundation

nonisolated struct CPUSampler: Sendable {
    private var previous: [CPUTicks] = []

    mutating func sample() -> CPUReading {
        let current = Self.ticks()
        defer { previous = current }
        let usage = CPUTicks.usage(current: current, previous: previous)
        var averages = [Double](repeating: 0, count: 3)
        let load: CPUReading.LoadAverage?
        if getloadavg(&averages, 3) == 3, averages.allSatisfy({ $0.isFinite && $0 >= 0 }) {
            load = CPUReading.LoadAverage(oneMinute: averages[0], fiveMinutes: averages[1], fifteenMinutes: averages[2])
        } else {
            load = nil
        }
        return CPUReading(usage: usage.total, cores: usage.cores, loadAverage: load)
    }

    mutating func reset() { previous = [] }

    private static func ticks() -> [CPUTicks] {
        var processors: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processors, &info, &count) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        guard processors > 0, Int(processors) <= Int(count) / stride else { return [] }
        return (0..<Int(processors)).map { index in
            let offset = index * stride
            return CPUTicks(user: UInt32(bitPattern: info[offset + Int(CPU_STATE_USER)]),
                            system: UInt32(bitPattern: info[offset + Int(CPU_STATE_SYSTEM)]),
                            idle: UInt32(bitPattern: info[offset + Int(CPU_STATE_IDLE)]),
                            nice: UInt32(bitPattern: info[offset + Int(CPU_STATE_NICE)]))
        }
    }
}
