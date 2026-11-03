import Darwin
import Foundation
import SystemConfiguration

nonisolated struct NetworkSampler: Sendable {
    private var delta = NetworkDelta()
    private var kinds: [String: NetworkReading.Kind] = [:]

    mutating func sample() -> NetworkReading? {
        guard let interface = Self.primaryInterface(), let counters = Self.counters(interface) else {
            _ = delta.update(nil)
            return nil
        }
        let rates = delta.update(.init(interface: interface, received: counters.0, sent: counters.1,
                                       time: ProcessInfo.processInfo.systemUptime))
        if kinds[interface] == nil { kinds[interface] = Self.kind(interface) }
        return NetworkReading(interface: interface, kind: kinds[interface] ?? .other,
                              addresses: Self.addresses(interface), downBytesPerSecond: rates.down,
                              upBytesPerSecond: rates.up, totalDown: delta.totalDown, totalUp: delta.totalUp)
    }

    private static func primaryInterface() -> String? {
        var primaryNames: [String] = []
        if let store = SCDynamicStoreCreate(nil, "NetworkSampler" as CFString, nil, nil) {
            for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
                if let state = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                   let name = state["PrimaryInterface"] as? String { primaryNames.append(name) }
            }
        }
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return nil }
        defer { freeifaddrs(first) }
        var current = first
        var interfaces: [NetworkInterfaceCandidate] = []
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            let name = String(cString: entry.ifa_name)
            let family = entry.ifa_addr?.pointee.sa_family
            interfaces.append(.init(name: name,
                                    isRunning: entry.ifa_flags & UInt32(IFF_UP | IFF_RUNNING)
                                        == UInt32(IFF_UP | IFF_RUNNING),
                                    hasAddress: family == UInt8(AF_INET) || family == UInt8(AF_INET6)))
        }
        return NetworkInterfaceCandidate.select(interfaces, primaryNames: primaryNames)
    }

    private static func counters(_ name: String) -> (UInt64, UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(if_nametoindex(name))]
        var size = 0
        guard mib.last != 0, sysctl(&mib, 6, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard bytes.withUnsafeMutableBytes({ sysctl(&mib, 6, $0.baseAddress, &size, nil, 0) }) == 0 else {
            return nil
        }
        return bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let length = Int(header.ifm_msglen)
                guard length >= MemoryLayout<if_msghdr>.size, offset + length <= size else { break }
                if header.ifm_type == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size {
                    let row = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    return (row.ifm_data.ifi_ibytes, row.ifm_data.ifi_obytes)
                }
                offset += length
            }
            return nil
        }
    }

    private static func kind(_ name: String) -> NetworkReading.Kind {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        guard let interface = interfaces.first(where: { SCNetworkInterfaceGetBSDName($0) as String? == name }) else {
            return .other
        }
        let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
        if type == kSCNetworkInterfaceTypeIEEE80211 as String { return .wifi }
        return type == kSCNetworkInterfaceTypeEthernet as String ? .ethernet : .other
    }

    private static func addresses(_ name: String) -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var result = Set<String>()
        var current = first
        while let entry = current?.pointee {
            defer { current = entry.ifa_next }
            guard String(cString: entry.ifa_name) == name, let address = entry.ifa_addr,
                  [UInt8(AF_INET), UInt8(AF_INET6)].contains(address.pointee.sa_family) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                if let address = String(bytes: bytes, encoding: .utf8) { result.insert(address) }
            }
        }
        return result.sorted()
    }
}
