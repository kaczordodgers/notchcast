// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's SystemMonitor, SystemInfo, NetworkSampler, DiskSampler and ProcessUsageService.

import AppKit
import Darwin
import Foundation

extension MonitorSystem {
    static func live() -> MonitorSystem {
        let (hidden, tolerance) = (MonitorBoard.hiddenInterval, MonitorBoard.hiddenTolerance)
        return MonitorSystem(
            read: { await MonitorLiveReads.read(detail: $0, previous: $1) },
            eject: { await MonitorLiveReads.eject($0) },
            sleep: { try await Task.sleep(for: $0, tolerance: $0 == hidden ? tolerance : nil) },
            processorCount: ProcessInfo.processInfo.activeProcessorCount)
    }
}

/// One host port for the app's life, so no read leaks a send right.
nonisolated private let monitorHost = mach_host_self()

/// Plain syscalls an unprivileged process may make; a read that fails is nil, never a guess.
enum MonitorLiveReads {
    @concurrent
    static func read(detail: Bool, previous: [Int32: UInt64]) async -> MonitorReading {
        MonitorReading(uptime: ProcessInfo.processInfo.systemUptime, cpu: cpu(), memory: memory(),
                       pressure: pressure(), disk: disk(), volumes: detail ? volumes() : nil,
                       network: detail ? network() : nil,
                       processes: detail ? processes(previous: previous) : nil)
    }

    nonisolated static func cpu() -> MonitorCPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(monitorHost, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return MonitorCPUTicks(user: UInt64(ticks.0), system: UInt64(ticks.1), idle: UInt64(ticks.2),
                               nice: UInt64(ticks.3))
    }

    nonisolated static func memory() -> MonitorMemory? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(monitorHost, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MonitorMemory(
            total: ProcessInfo.processInfo.physicalMemory, pageSize: UInt64(getpagesize()),
            internalPages: UInt64(stats.internal_page_count), purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count), compressorPages: UInt64(stats.compressor_page_count))
    }

    nonisolated static func pressure() -> MonitorPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .unknown }
        return MonitorPressure(kernelLevel: level)
    }

    nonisolated static func disk() -> MonitorDisk? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(filePath: "/").resourceValues(forKeys: keys) else { return nil }
        func positive<T: BinaryInteger>(_ value: T?) -> UInt64? { value.flatMap { $0 >= 0 ? UInt64($0) : nil } }
        return MonitorDisk(total: positive(values.volumeTotalCapacity), rawFree: positive(values.volumeAvailableCapacity),
                           importantFree: positive(values.volumeAvailableCapacityForImportantUsage))
    }

    nonisolated static func volumes() -> [MonitorVolume] {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeIsInternalKey,
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys),
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return MonitorVolume(
                path: url.path, name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
                size: values.volumeTotalCapacity.flatMap(UInt64.init(exactly:)), isInternal: values.volumeIsInternal,
                isRemovable: values.volumeIsRemovable, isEjectable: values.volumeIsEjectable,
                isLocal: values.volumeIsLocal, isRootFileSystem: values.volumeIsRootFileSystem)
        }
    }

    @concurrent
    static func eject(_ path: String) async -> MonitorEjectResult {
        do {
            try Task.checkCancellation()
            try await FileManager.default.unmountVolume(at: URL(filePath: path),
                                                        options: [.allPartitionsAndEjectDisk, .withoutUI])
            return MonitorEjectResult()
        } catch let error as NSError {
            let mounts = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])
            let stillMounted = mounts?.contains { $0.path == path } ?? true
            let pid = (error.userInfo[NSFileManagerUnmountDissentingProcessIdentifierErrorKey] as? NSNumber)?.int32Value
            let holder: String? = if let pid, pid > 0 {
                NSRunningApplication(processIdentifier: pid)?.localizedName ?? name(pid)
            } else {
                nil
            }
            return MonitorEjectResult(errorDomain: error.domain, errorCode: error.code, holder: holder,
                                      stillMounted: stillMounted)
        }
    }

    /// 64-bit counters from the routing socket (`NET_RT_IFLIST2`); `getifaddrs`' 32-bit ones wrap.
    nonisolated static func network() -> MonitorNetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }
        var counters = MonitorNetworkCounters(received: 0, sent: 0, interfaces: [])
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = base.advanced(by: offset).loadUnaligned(as: if_msghdr.self)
                let size = Int(header.ifm_msglen)
                guard size > 0, offset + size <= length else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = base.advanced(by: offset).loadUnaligned(as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(info.ifm_index), &name) != nil {
                        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                        let interface = String(bytes: bytes, encoding: .utf8) ?? ""
                        if MonitorNetworkCounters.counts(interface), counters.interfaces.insert(interface).inserted {
                            counters.received &+= info.ifm_data.ifi_ibytes
                            counters.sent &+= info.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += size
            }
        }
        return counters
    }

    /// Every process libproc lets this user read (another user's needs root); only the rows listed get a name.
    nonisolated static func processes(previous: [Int32: UInt64]) -> [MonitorProcessTime] {
        guard let timebase = NotchcastProcesses.timebase(), timebase.denom > 0 else { return [] }
        let times = NotchcastProcesses.pids().compactMap { pid -> MonitorProcessTime? in
            guard let usage = NotchcastProcesses.usage(pid) else { return nil }
            let scaled = usage.cpuTicks.multipliedFullWidth(by: UInt64(timebase.numer))
            guard scaled.high < UInt64(timebase.denom) else { return nil }
            let nanoseconds = UInt64(timebase.denom).dividingFullWidth(scaled).quotient
            return MonitorProcessTime(pid: pid, cpuNanoseconds: nanoseconds, footprint: usage.footprint)
        }
        let listed = Set(MonitorBoard.ranked(times, since: previous).map(\.pid))
        return times.map { process in
            var process = process
            if listed.contains(process.pid) { process.name = name(process.pid) }
            return process
        }
    }

    nonisolated static func name(_ pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(bytes: buffer.prefix(Int(length)), encoding: .utf8) : nil
    }
}
