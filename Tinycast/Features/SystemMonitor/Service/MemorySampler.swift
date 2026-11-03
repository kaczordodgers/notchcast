import Darwin
import Foundation

nonisolated struct MemorySampler: Sendable {
    func read() -> MemoryReading? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
            / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0
        return MemoryDecoder.decode(
            total: ProcessInfo.processInfo.physicalMemory, pageSize: UInt64(pageSize),
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count), wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            externalPages: UInt64(stats.external_page_count), freePages: UInt64(stats.free_count),
            pressureLevel: integer("kern.memorystatus_vm_pressure_level"),
            availablePercent: integer("kern.memorystatus_level"),
            swapUsed: hasSwap ? swap.xsu_used : nil, swapTotal: hasSwap ? swap.xsu_total : nil)
    }

    private func integer(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}
